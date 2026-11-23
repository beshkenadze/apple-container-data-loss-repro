#!/bin/bash
# A1. A volume create under a name that differs only in case from an existing volume formats the
# existing volume's image, then answers "already exists". The data in the existing volume is lost.
#
# Needs debugfs from e2fsprogs (brew install e2fsprogs). It writes a file into the new volume's
# image without a VM, and reads it back.

source "$(dirname "$0")/common.sh"

DEBUGFS="${DEBUGFS:-$(command -v debugfs || echo "$(brew --prefix e2fsprogs 2>/dev/null)/sbin/debugfs")}"
[[ -x "$DEBUGFS" ]] || fail "debugfs not found; install e2fsprogs (brew install e2fsprogs) or set DEBUGFS"

FIRST="vfold$RUN"
SECOND="$(upper "$FIRST")"

require_system
require_folding "$ROOT/volumes"
require_absent "$FIRST"

IMG="$ROOT/volumes/$FIRST/volume.img"
DATA="$(mktemp -d)"
trap 'rm -rf -- "$DATA"; cleanup' EXIT
printf 'data written by run %s\n' "$RUN" >"$DATA/precious.txt"

step "Create volume $FIRST and put a file in it"
run "$C" volume create --opt size=64M "$FIRST"
[[ $RC -eq 0 ]] || fail "volume create $FIRST failed"
made volume delete "$FIRST"
run "$DEBUGFS" -w -R "write $DATA/precious.txt precious.txt" "$IMG"
run "$DEBUGFS" -R "cat /precious.txt" "$IMG"
[[ "$OUT" == *"data written by run $RUN"* ]] || fail "the file could not be written into $IMG"
run "$DEBUGFS" -R "ls -l /" "$IMG"
listing "$ROOT/volumes"
BEFORE="$(digest "$IMG")"
say "sha256 of $FIRST/volume.img: $BEFORE"

step "Create volume $SECOND (the same name in another case)"
run "$C" volume create --opt size=64M "$SECOND"
CREATE_RC=$RC
CREATE_OUT="$OUT"
[[ $CREATE_RC -eq 0 ]] && made volume delete "$SECOND"

step "Read volume $FIRST again"
run "$C" volume list
listing "$ROOT/volumes"
AFTER="$(digest "$IMG")"
say "sha256 of $FIRST/volume.img: $AFTER"
run "$DEBUGFS" -R "ls -l /" "$IMG"
run "$DEBUGFS" -R "cat /precious.txt" "$IMG"
READ_BACK="$OUT"

if [[ "$READ_BACK" != *"data written by run $RUN"* ]]; then
    defect "create $SECOND answered '${CREATE_OUT//$'\n'/ }' (status $CREATE_RC); /precious.txt in $FIRST is gone and the image changed ($BEFORE -> $AFTER)"
fi
if [[ $CREATE_RC -eq 0 ]]; then
    defect "create $SECOND succeeded: two volume names now share the directory of $FIRST"
fi
if [[ "$BEFORE" != "$AFTER" ]]; then
    fail "the image of $FIRST changed although the file is still there; inspect the output"
fi
no_defect "create $SECOND was refused ('${CREATE_OUT//$'\n'/ }'); $FIRST still holds /precious.txt and its image is unchanged"
