#!/bin/bash
# B. When the API server starts and a container fails to load, the server deletes the container's
# directory. One cause is a runtime plugin that is not installed at that moment.
#
# The script makes one container, then sets the runtime plugin name in that container's
# configuration to a name that no installed plugin has. This is the state of a container whose
# plugin was removed or is not yet installed. Then it restarts the container system.
#
# The restart stops every running container on this Mac. The script refuses to run unless
# REPRO_ALLOW_RESTART=1 is set.

source "$(dirname "$0")/common.sh"

[[ "${REPRO_ALLOW_RESTART:-0}" == 1 ]] ||
    fail "this script restarts the container system and stops all running containers; set REPRO_ALLOW_RESTART=1 to allow it"
command -v jq >/dev/null 2>&1 || fail "jq not found"

NAME="bload$RUN"
PLUGIN="container-runtime-absent-$RUN"

require_system
DEFAULT_ROOT="$HOME/Library/Application Support/com.apple.container"
[[ "$ROOT" -ef "$DEFAULT_ROOT" ]] ||
    fail "the system uses the data root $ROOT; the script restarts it with the default root only"
require_absent "$NAME"

DIR="$ROOT/containers/$NAME"
CONFIG="$DIR/runtime-configuration.json"

step "Create container $NAME"
run "$C" image pull "$IMAGE"
[[ $RC -eq 0 ]] || fail "image pull failed"
run "$C" create --name "$NAME" --network none "$IMAGE" true
[[ $RC -eq 0 ]] || fail "create $NAME failed"
made delete --force "$NAME"
listing "$DIR"
say "runtime plugin in its configuration: $(jq -r '.. | objects | .runtimeHandler? // empty' "$CONFIG" | head -1)"

step "Stop the container system"
run "$C" system stop
[[ $RC -eq 0 ]] || fail "system stop failed"

step "Name a runtime plugin that is not installed: $PLUGIN"
TMP="$(mktemp)"
jq --arg p "$PLUGIN" 'walk(if type == "object" and has("runtimeHandler") then .runtimeHandler = $p else . end)' \
    "$CONFIG" >"$TMP" && cat "$TMP" >"$CONFIG"
rm -f -- "$TMP"
say "runtime plugin in its configuration: $(jq -r '.. | objects | .runtimeHandler? // empty' "$CONFIG" | head -1)"
listing "$DIR"
BEFORE="$(digest "$CONFIG")"
say "sha256 of $NAME/runtime-configuration.json: $BEFORE"

step "Start the container system"
run "$C" system start </dev/null
[[ $RC -eq 0 ]] || fail "system start failed; start it again with '$C system start'"

step "Look for container $NAME"
run "$C" list --all
LISTED=no
printf '%s\n' "$OUT" | awk '{print $1}' | grep -qx -- "$NAME" && LISTED=yes
listing "$DIR"
run "$C" start "$NAME"

if [[ ! -d "$DIR" ]]; then
    [[ $LISTED == yes ]] || CLEANUP=()
    defect "after the restart the directory of $NAME is gone (listed: $LISTED); its configuration and everything else in it were deleted"
fi
[[ "$(digest "$CONFIG")" == "$BEFORE" ]] || fail "the directory stays but its configuration changed; inspect the output"
no_defect "after the restart the directory of $NAME and its configuration are unchanged (listed: $LISTED)"
