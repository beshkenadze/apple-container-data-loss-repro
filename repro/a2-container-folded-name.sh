#!/bin/bash
# A2. A container create under a name that differs only in case from an existing container writes
# its runtime configuration into the existing container's directory. A delete of the new name then
# removes that directory, while the first container is still listed.
#
# Without a VM the first container is created but not started, so its directory holds only
# runtime-configuration.json. On a Mac where the first container has run, the same directory also
# holds its root file system (rootfs.ext4), and the delete removes it too.

source "$(dirname "$0")/common.sh"

FIRST="cfold$RUN"
SECOND="$(upper "$FIRST")"

require_system
require_folding "$ROOT/containers"
require_absent "$FIRST"

DIR="$ROOT/containers/$FIRST"
CONFIG="$DIR/runtime-configuration.json"
config_id() { sed -n 's/.*"id" *: *"\([^"]*\)".*/\1/p' "$CONFIG" 2>/dev/null | grep -i -m1 -- "$FIRST" || echo absent; }

step "Create container $FIRST"
run "$C" image pull "$IMAGE"
[[ $RC -eq 0 ]] || fail "image pull failed"
run "$C" create --name "$FIRST" --network none "$IMAGE" true
[[ $RC -eq 0 ]] || fail "create $FIRST failed"
made delete --force "$FIRST"
listing "$DIR"
BEFORE="$(digest "$CONFIG")"
say "sha256 of $FIRST/runtime-configuration.json: $BEFORE"
say "container ID in that file: $(config_id)"

step "Create container $SECOND (the same name in another case)"
run "$C" create --name "$SECOND" --network none "$IMAGE" true
CREATE_RC=$RC
CREATE_OUT="$OUT"
listing "$DIR"
AFTER="$(digest "$CONFIG")"
say "sha256 of $FIRST/runtime-configuration.json: $AFTER"
say "container ID in that file: $(config_id)"
run "$C" list --all

if [[ $CREATE_RC -ne 0 ]]; then
    [[ "$BEFORE" == "$AFTER" ]] ||
        defect "create $SECOND failed ('${CREATE_OUT//$'\n'/ }') but changed the runtime configuration of $FIRST ($BEFORE -> $AFTER)"
    [[ "$CREATE_OUT" == *"$FIRST"* || "$CREATE_OUT" == *"exist"* ]] ||
        fail "create $SECOND failed for another reason: ${CREATE_OUT//$'\n'/ }"
    no_defect "create $SECOND was refused ('${CREATE_OUT//$'\n'/ }'); the directory and runtime configuration of $FIRST are unchanged"
fi

step "Delete container $SECOND"
run "$C" delete "$SECOND"
[[ $RC -eq 0 ]] || made delete --force "$SECOND"
run "$C" list --all
LISTED=no
printf '%s\n' "$OUT" | awk '{print $1}' | grep -qx -- "$FIRST" && LISTED=yes
listing "$DIR"
run "$C" inspect "$FIRST"

if [[ ! -d "$DIR" && $LISTED == yes ]]; then
    defect "create $SECOND succeeded and rewrote the runtime configuration of $FIRST ($BEFORE -> $AFTER); delete $SECOND removed the directory of $FIRST, which is still listed"
fi
if [[ "$BEFORE" != "$AFTER" ]]; then
    defect "create $SECOND succeeded and rewrote the runtime configuration of $FIRST ($BEFORE -> $AFTER)"
fi
fail "create $SECOND succeeded without changing $FIRST; inspect the output"
