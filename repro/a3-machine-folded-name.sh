#!/bin/bash
# A3. A machine create under a name that differs only in case from an existing machine writes into
# the existing machine's bundle.
#
# Both machines are created with --no-boot, so no VM is needed.

source "$(dirname "$0")/common.sh"

MACHINE_IMAGE="docker.io/library/alpine:3.22"
FIRST="mfold$RUN"
SECOND="$(upper "$FIRST")"

require_system
MACHINES="$ROOT/plugin-state/machine-apiserver/machines"
require_folding "$MACHINES"
require_absent "$FIRST"

BUNDLE="$MACHINES/$FIRST"
config_id() { sed -n 's/.*"id" *: *"\([^"]*\)".*/\1/p' "$BUNDLE/config.json" 2>/dev/null | head -1; }
state() { # the files of the bundle with their SHA-256, and the root file system's inode
    local f
    for f in "$BUNDLE"/*; do
        [[ -f "$f" ]] || continue
        if [[ "$(basename "$f")" == rootfs.ext4 ]]; then
            printf '%s inode %s\n' "$(basename "$f")" "$(stat -f '%i' "$f")"
        else
            printf '%s %s\n' "$(basename "$f")" "$(digest "$f")"
        fi
    done
}

step "Create machine $FIRST (no boot)"
run "$C" machine create "$MACHINE_IMAGE" --name "$FIRST" --no-boot
if [[ $RC -ne 0 ]]; then
    [[ -d "$BUNDLE" ]] && made machine delete "$FIRST"
    fail "machine create $FIRST failed"
fi
made machine delete "$FIRST"
listing "$BUNDLE"
BEFORE="$(state)"
say "bundle state of $FIRST:"
printf '%s\n' "$BEFORE" | sed 's/^/    /'
say "machine ID in $FIRST/config.json: $(config_id)"
[[ -n "$BEFORE" ]] || fail "the bundle of $FIRST holds no files"

step "Create machine $SECOND (the same name in another case, no boot)"
run "$C" machine create "$MACHINE_IMAGE" --name "$SECOND" --no-boot
CREATE_RC=$RC
CREATE_OUT="$OUT"
run "$C" machine list
printf '%s\n' "$OUT" | awk 'NR > 1 {print $1}' | grep -qx -- "$SECOND" && made machine delete "$SECOND"
listing "$BUNDLE"
AFTER="$(state)"
say "bundle state of $FIRST:"
printf '%s\n' "$AFTER" | sed 's/^/    /'
say "machine ID in $FIRST/config.json: $(config_id)"
say "changed lines (before / after):"
diff <(printf '%s\n' "$BEFORE") <(printf '%s\n' "$AFTER") | sed 's/^/    /'

if [[ "$BEFORE" != "$AFTER" ]]; then
    defect "create $SECOND (status $CREATE_RC: '${CREATE_OUT//$'\n'/ }') changed the bundle of $FIRST"
fi
if [[ $CREATE_RC -eq 0 ]]; then
    defect "create $SECOND succeeded: two machine names now share the bundle of $FIRST"
fi
[[ "$CREATE_OUT" == *"$FIRST"* || "$CREATE_OUT" == *"exist"* ]] ||
    fail "create $SECOND failed for another reason: ${CREATE_OUT//$'\n'/ }"
no_defect "create $SECOND was refused ('${CREATE_OUT//$'\n'/ }'); the bundle of $FIRST is unchanged"
