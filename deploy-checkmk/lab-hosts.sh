#!/bin/bash
#
# Fake OpenStack VMs for the Checkmk test instance.
#
# Each file fixtures/<host>.txt is the agent output of one host. Checkmk reads it
# with "cat" instead of contacting an agent, so no VM or database is needed.
#
#   ./lab-hosts.sh sync                        add hosts for all fixtures, remove the
#                                              others, discover services and activate
#   ./lab-hosts.sh state <host> <pattern> <0-3>  set the state of matching services
#   ./lab-hosts.sh recheck [host]              check now instead of waiting a minute
#
# Example: ./lab-hosts.sh state vm-db02 "Replication Check - pg-hr" 0
#
# For a further instance started with CMK_LAB=<name>, set the same CMK_LAB and
# CMK_WEB_PORT here; its fixtures are in fixtures-<name>/.

set -euo pipefail

CMK_SITE="${CMK_SITE:-cmk}"
CMK_PASSWORD="${CMK_PASSWORD:-cmkadmin}"
CMK_WEB_PORT="${CMK_WEB_PORT:-8080}"

CMK_LAB="${CMK_LAB:-}"
CONTAINER="checkmk-lab${CMK_LAB:+-$CMK_LAB}"
FOLDER="lab"
FIXTURES="$(dirname "$(realpath "$0")")/fixtures${CMK_LAB:+-$CMK_LAB}"
API="http://localhost:$CMK_WEB_PORT/$CMK_SITE/check_mk/api/1.0"
RULE_DESCRIPTION="Lab: agent output from fixture files"

api() { # method path [json]
  curl -sf -X "$1" \
    -H "Authorization: Bearer cmkadmin $CMK_PASSWORD" \
    -H "Accept: application/json" \
    -H "Content-Type: application/json" \
    -H "If-Match: *" \
    "$API$2" ${3:+-d "$3"}
}

fixture_hosts() {
  find "$FIXTURES" -maxdepth 1 -name '*.txt' -printf '%f\n' | sed 's/\.txt$//' | sort
}

lab_hosts() {
  api GET "/objects/folder_config/~$FOLDER/collections/hosts" | jq -r '.value[].id' | sort
}

ensure_rule() { # ruleset description value_raw
  api GET "/domain-types/rule/collections/all?ruleset_name=$1" |
    jq -e --arg d "$2" '.value[] | select(.extensions.properties.description == $d)' >/dev/null && return

  api POST /domain-types/rule/collections/all "$(jq -nc --arg r "$1" --arg d "$2" --arg v "$3" --arg f "/$FOLDER" \
    '{ruleset: $r, folder: $f, properties: {description: $d}, value_raw: $v, conditions: {}}')" >/dev/null
}

sync() {
  api GET "/objects/folder_config/~$FOLDER" >/dev/null 2>&1 ||
    api POST /domain-types/folder_config/collections/all \
      '{"name": "'"$FOLDER"'", "title": "Lab", "parent": "/"}' >/dev/null

  ensure_rule datasource_programs "$RULE_DESCRIPTION" '"cat /fixtures/$HOSTNAME$.txt"'
  # Rootless podman cannot send ICMP, so take the host state from the agent instead of ping
  ensure_rule host_check_commands "Lab: host state from agent, rootless podman cannot ping" '"agent"'

  local existing
  existing="$(lab_hosts)"

  for host in $(comm -23 <(fixture_hosts) <(echo "$existing")); do
    echo "+ $host"
    api POST /domain-types/host_config/collections/all \
      '{"folder": "/'"$FOLDER"'", "host_name": "'"$host"'", "attributes": {"ipaddress": "127.0.0.1"}}' >/dev/null
  done

  for host in $(comm -13 <(fixture_hosts) <(echo "$existing")); do
    echo "- $host"
    api DELETE "/objects/host_config/$host" >/dev/null
  done

  # Rediscover every host, so services added to or removed from a fixture show up too
  for host in $(fixture_hosts); do
    api POST /domain-types/service_discovery_run/actions/start/invoke \
      '{"host_name": "'"$host"'", "mode": "tabula_rasa"}' >/dev/null
    until api GET "/objects/service_discovery_run/$host" | jq -e '.extensions.active == false' >/dev/null; do
      sleep 1
    done
  done

  activate
  sleep 3
  recheck
  echo "Synced $(fixture_hosts | wc -l) hosts"
}

activate() {
  local id
  # Answers 422 when there is nothing to activate
  id="$(api POST /domain-types/activation_run/actions/activate-changes/invoke \
    '{"redirect": false, "sites": ["'"$CMK_SITE"'"], "force_foreign_changes": true}' | jq -r .id)" || return 0
  until api GET "/objects/activation_run/$id" | jq -e '.extensions.is_running == false' >/dev/null; do
    sleep 1
  done
}

state() { # host pattern state
  local file="$FIXTURES/$1.txt"
  [[ -f "$file" && "$3" =~ ^[0-3]$ ]] || { echo "usage: $0 state <host> <pattern> <0-3>" >&2; exit 1; }
  grep -qF -- "$2" "$file" || { echo "No service matching '$2' in $file" >&2; exit 1; }

  # Only touch local check lines, i.e. those starting with a state
  awk -v p="$2" -v s="$3" 'index($0, p) && /^[0-3P] / { $0 = s substr($0, 2) } 1' "$file" > "$file.tmp"
  mv "$file.tmp" "$file"
  grep -F -- "$2" "$file"
  recheck "$1"
}

recheck() { # [host]
  local hosts="${1:-$(fixture_hosts)}"
  for host in $hosts; do
    podman exec -u "$CMK_SITE" "$CONTAINER" bash -lc \
      't=$(date +%s); lq "COMMAND [$t] SCHEDULE_FORCED_HOST_CHECK;'"$host"';$t"; lq "COMMAND [$t] SCHEDULE_FORCED_SVC_CHECK;'"$host"';Check_MK;$t"'
  done
}

case "${1:-}" in
  sync) sync ;;
  state) shift; state "$@" ;;
  recheck) recheck "${2:-}" ;;
  *) sed -n '3,17p' "$0" | sed 's/^# \{0,1\}//'; exit 1 ;;
esac
