#!/bin/bash
#
# Disposable Checkmk test instance (rootless podman).
#
#   ./checkmk.sh up        create and start the container
#   ./checkmk.sh down      stop and remove the container (data is kept)
#   ./checkmk.sh purge     remove container, volume and network
#   ./checkmk.sh status    show container state
#   ./checkmk.sh logs      follow the container log
#   ./checkmk.sh secret    print the API secret of the read-only user "omarchy"
#   ./checkmk.sh password  print the password of the administrator "cmkadmin"
#   ./checkmk.sh shell     open a shell as the site user
#
# The ports only listen on this machine (127.0.0.1), and a new instance gets a
# random administrator password, kept next to this script in cmkadmin.secret.
# CMK_BIND=0.0.0.0 would open the ports to the network: only do that behind a
# firewall, and with a password of your own in CMK_PASSWORD.
#
# Everything can be overridden through the environment, e.g.
#   CMK_IMAGE=docker.io/checkmk/check-mk-raw:2.4.0p37 ./checkmk.sh up
#
# CMK_LAB runs a further, independent instance next to the default one, with its
# own container, volume, secret and fixtures-<name>/ folder:
#   CMK_LAB=staging CMK_WEB_PORT=8081 CMK_AGENT_PORT=8001 ./checkmk.sh up

set -euo pipefail

CMK_IMAGE="${CMK_IMAGE:-docker.io/checkmk/check-mk-community:2.5.0p15}"
CMK_SITE="${CMK_SITE:-cmk}"
CMK_WEB_PORT="${CMK_WEB_PORT:-8080}"
CMK_AGENT_PORT="${CMK_AGENT_PORT:-8000}"
CMK_BIND="${CMK_BIND:-127.0.0.1}"

CMK_LAB="${CMK_LAB:-}"
SUFFIX="${CMK_LAB:+-$CMK_LAB}"

CONTAINER="checkmk-lab$SUFFIX"
VOLUME="checkmk-lab$SUFFIX-sites"
# Shared network, in case other lab containers need to reach Checkmk by name
NETWORK="checkmk-lab"

# Read-only automation user for the Omarchy plugin, its secret is kept next to this script
API_USER="omarchy"
SCRIPT_DIR="$(dirname "$(realpath "$0")")"
SECRET_FILE="$SCRIPT_DIR/$API_USER$SUFFIX.secret"
ADMIN_FILE="$SCRIPT_DIR/cmkadmin$SUFFIX.secret"
FIXTURES="$SCRIPT_DIR/fixtures$SUFFIX"
API="http://localhost:$CMK_WEB_PORT/$CMK_SITE/check_mk/api/1.0"

# The administrator password: CMK_PASSWORD, the one kept in cmkadmin.secret,
# or "cmkadmin" for an instance from before the random passwords
admin_password() {
  if [[ -n "${CMK_PASSWORD:-}" ]]; then printf '%s' "$CMK_PASSWORD"
  elif [[ -s "$ADMIN_FILE" ]]; then tr -d '\n' < "$ADMIN_FILE"
  else printf cmkadmin
  fi
}

# Requests as the administrator; the password goes to curl through a file
# descriptor, not on its command line
admin_curl() { # curl arguments
  curl -H @<(printf 'Authorization: Bearer cmkadmin %s\n' "$(admin_password)") "$@"
}

up() {
  mkdir -p "$FIXTURES"
  podman network exists "$NETWORK" || podman network create "$NETWORK" >/dev/null

  if podman container exists "$CONTAINER"; then
    podman start "$CONTAINER" >/dev/null
    if [[ -z "${CMK_PASSWORD:-}" && ! -s "$ADMIN_FILE" ]]; then
      echo "This instance still has the administrator password cmkadmin. For a random one:"
      echo "  ${0##*/} purge && ${0##*/} up"
    fi
  else
    # A new site gets a random administrator password, unless one is given
    if [[ -z "${CMK_PASSWORD:-}" && ! -s "$ADMIN_FILE" ]]; then
      (umask 077; head -c 32 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' > "$ADMIN_FILE")
    fi
    podman run -d \
      --name "$CONTAINER" \
      --hostname "$CONTAINER" \
      --network "$NETWORK" \
      -p "$CMK_BIND:$CMK_WEB_PORT:5000" \
      -p "$CMK_BIND:$CMK_AGENT_PORT:8000" \
      -v "$VOLUME:/omd/sites" \
      -v /etc/localtime:/etc/localtime:ro \
      -v "$FIXTURES:/fixtures:ro" \
      -e CMK_SITE_ID="$CMK_SITE" \
      --env-file <(printf 'CMK_PASSWORD=%s\n' "$(admin_password)") \
      "$CMK_IMAGE" >/dev/null
  fi

  echo -n "Waiting for Checkmk to come up "
  until curl -sf -o /dev/null "http://localhost:$CMK_WEB_PORT/$CMK_SITE/check_mk/login.py"; do
    echo -n "."
    sleep 2
  done
  echo

  create_api_user

  cat <<EOF

  Web UI    http://localhost:$CMK_WEB_PORT/$CMK_SITE/
  Login     cmkadmin, password: ${0##*/} password
  API       $API/
  API user  $API_USER, secret in $SECRET_FILE
EOF
}

create_api_user() {
  if [[ -s "$SECRET_FILE" ]] && api_ok "$API_USER $(cat "$SECRET_FILE")"; then
    return
  fi

  local secret
  secret="$(head -c 32 /dev/urandom | base64 | tr -dc 'A-Za-z0-9')"
  # Recreate the user, so a lost secret file is fixed by simply running up again
  admin_curl -s -o /dev/null -X DELETE "$API/objects/user_config/$API_USER"
  # The new secret goes in the request body, read from a file descriptor
  admin_curl -sf -o /dev/null -X POST \
    -H "Content-Type: application/json" \
    "$API/domain-types/user_config/collections/all" \
    --data-binary @<(jq -n --arg user "$API_USER" --rawfile secret <(printf '%s' "$secret") '{
      username: $user,
      fullname: "Omarchy plugin (read-only)",
      roles: ["guest"],
      auth_option: {auth_type: "automation", secret: $secret}
    }')

  (umask 077; echo "$secret" > "$SECRET_FILE")
  api_ok "$API_USER $secret" || { echo "Could not create API user $API_USER" >&2; exit 1; }
}

api_ok() { # user and secret
  curl -sf -o /dev/null -H @<(printf 'Authorization: Bearer %s\n' "$1") -H "Accept: application/json" "$API/version"
}

down() {
  podman rm -f "$CONTAINER" >/dev/null 2>&1 || true
  echo "Container removed, data kept in volume $VOLUME"
}

purge() {
  down
  podman volume rm -f "$VOLUME" >/dev/null 2>&1 || true
  # Other lab instances may still use the network
  podman network rm "$NETWORK" >/dev/null 2>&1 || true
  rm -f "$SECRET_FILE" "$ADMIN_FILE"
  echo "Volume, network, API secret and administrator password removed"
}

case "${1:-}" in
  up) up ;;
  down) down ;;
  purge) purge ;;
  status) podman ps -a --filter "name=^$CONTAINER\$" --format '{{.Names}}  {{.Status}}  {{.Ports}}' ;;
  logs) podman logs -f "$CONTAINER" ;;
  secret) cat "$SECRET_FILE" ;;
  password) admin_password; echo ;;
  shell) podman exec -it -u "$CMK_SITE" "$CONTAINER" bash -l ;;
  *) sed -n '3,/^$/p' "$0" | sed '$d; s/^# \{0,1\}//'; exit 1 ;;
esac
