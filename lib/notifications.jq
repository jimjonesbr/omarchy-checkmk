# The notifications of one poll: what changed since the previous one.
#
#   jq -c --slurpfile prev <previous status> --argjson max <n> -f notifications.jq <status>
#
# Prints a JSON array of {urgency, title, body, target} for checkmk-notify:
# servers that became unreachable or reachable again, and services whose hard
# state changed, one each or, beyond max, one summary. A server polled for the
# first time announces nothing, nor does locking or unlocking one, nor a muted
# server. Services of a server that failed are stale, not changed.
def key: (.server // "") + "\u0000" + .host + "\u0000" + .service;
def name: ["OK", "WARN", "CRIT", "UNKNOWN"][.] // "?";
def where($multi): .host + (if $multi then " · " + .serverName else "" end);
$prev[0] as $prev
| (.servers | length > 1) as $multi
| [ .servers[] | select(.muted) | .id ] as $muted
| ($prev.servers // [] | map({key: .id, value: (if .locked then "locked" else .ok end)}) | from_entries) as $was
| [ .servers[] | . as $s
    | select(($s.muted | not) and ($s.locked | not) and ($was | has($s.id)) and $was[$s.id] != "locked" and $was[$s.id] != $s.ok)
    | if .ok then {urgency: "low", title: "Checkmk: \(.name) reachable again", body: "", target: "servers"}
      else {urgency: "normal", title: "Checkmk: \(.name) unreachable", body: .error, target: "servers"} end
  ] as $servers
# Hard states only: a soft state clears or is confirmed on the next checks.
# Status files from before hardState fall back to the state.
| ($prev.services // [] | map(select(.stale | not) | {key: key, value: (.hardState // .state)}) | from_entries) as $before
# The row of a down host only exists while it is down: a new one was UP before,
# as long as its server answered last time
| [ $prev.servers // [] | .[] | select(.ok) | .id ] as $answered
| [ .services[] | select((.handled | not) and (.stale | not)) | . as $x | select($muted | index($x.server) | not)
    | . + {state: (.hardState // .state)}
    | key as $k
    | (if $before | has($k) then $before[$k] elif .isHost and ($answered | index($x.server)) then 0 else null end) as $was
    | select($was != null and $was != .state) | . + {before: $was} ] as $changed
| $servers + if ($changed | length) > $max then
    # Too many for one each: a summary
    [ {urgency: (if any($changed[]; .state == 2) then "critical" elif any($changed[]; .state != 0) then "normal" else "low" end),
       title: "Checkmk: \($changed | length) services changed state",
       body: ([ $changed[0:$max][] | "\(.state | name)  \(.service) on \(where($multi))" ] | join("\n"))
         + "\n… and \(($changed | length) - $max) more",
       target: "problems"} ]
  else
    [ $changed[]
      | {urgency: (if .state == 2 then "critical" elif .state == 0 then "low" else "normal" end),
         title: (if .isHost then (if .state == 2 then "DOWN" else "UNREACHABLE" end) + "  " + .host
                 else "\(.state | name)  \(.service)" end),
         body: (if .isHost then (if $multi then .serverName + "\n" else "" end) + .output
                else "\(where($multi)) (was \(.before | name))\n\(.output)" end),
         target: (if .isHost then "host:\(.server)/\(.host)" else "service:\(.server)/\(.host)/\(.service)" end)} ]
  end
