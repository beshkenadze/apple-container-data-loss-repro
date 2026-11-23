# Shared helpers for the reproduction scripts. The scripts source this file.
#
# Every script prints its steps, the commands it runs and their answers, and ends with one line:
#   DEFECT REPRODUCED   exit status 1
#   NO DEFECT           exit status 0
# When the reproduction cannot run (no container system, a name is taken, a step failed), the
# script prints ERROR and exits with status 2, without a result line.

set -u

C="${C:-container}"
IMAGE="docker.io/library/busybox:1.37-musl"
RUN="$(uuidgen | tr -d '-' | tr 'A-Z' 'a-z' | cut -c 1-8)"
CLEANUP=()
CLEANED=0

say() { printf '%s\n' "$*"; }
step() { printf '\n== %s\n' "$*"; }
upper() { printf '%s' "$1" | tr 'a-z' 'A-Z'; }

# Prints a command, runs it, prints its output and status. Sets OUT and RC.
run() {
    printf '$ %s\n' "$*"
    OUT="$("$@" 2>&1)"
    RC=$?
    [[ -n "$OUT" ]] && printf '%s\n' "$OUT" | sed 's/^/    /'
    printf '    (exit status %s)\n' "$RC"
    return 0
}

# Records a cleanup command: the arguments to the container CLI that remove an object this run made.
made() { CLEANUP+=("$*"); }

cleanup() {
    [[ $CLEANED -eq 1 ]] && return 0
    CLEANED=1
    [[ ${#CLEANUP[@]} -eq 0 ]] && return 0
    step "Remove what this run made"
    local i
    for ((i = ${#CLEANUP[@]} - 1; i >= 0; i--)); do
        # shellcheck disable=SC2086 # the entries are CLI arguments without spaces
        run "$C" ${CLEANUP[i]}
    done
}
trap cleanup EXIT

fail() {
    say ""
    say "ERROR: $*"
    cleanup
    say ""
    say "The reproduction did not run to the end. No result."
    exit 2
}

result() { # exit-status line evidence
    cleanup
    say ""
    say "Evidence: $3"
    say "$2"
    exit "$1"
}
defect() { result 1 "DEFECT REPRODUCED" "$*"; }
no_defect() { result 0 "NO DEFECT" "$*"; }

# Finds the container system that the CLI talks to and its data root (ROOT).
require_system() {
    command -v "$C" >/dev/null 2>&1 || fail "the command '$C' is not found"
    step "The container system under test"
    run "$C" system status
    [[ $RC -eq 0 ]] || fail "the container system does not answer; start it with '$C system start'"
    ROOT="$(printf '%s\n' "$OUT" | awk '$1 == "paths.appRoot" { sub(/^[^ ]+ +/, ""); print }')"
    ROOT="${ROOT%/}"
    [[ -n "$ROOT" && -d "$ROOT" ]] || fail "the system reports no usable data root (paths.appRoot)"
    say "data root: $ROOT"
    say "run id: $RUN"
}

# Stops unless the directory compares names without case, as the macOS default volume does.
require_folding() { # directory
    local dir="$1"
    while [[ ! -d "$dir" ]]; do dir="$(dirname "$dir")"; done
    local probe="$dir/.repro-case-probe-$RUN"
    (set -o noclobber; : >"$probe") 2>/dev/null || fail "cannot write the probe file $probe"
    local folds=0
    [[ -e "$dir/$(upper ".repro-case-probe-$RUN")" ]] && folds=1
    rm -f -- "$probe"
    [[ $folds -eq 1 ]] || fail "$dir is on a case-sensitive file system; this defect needs the macOS default (case-insensitive)"
    say "$dir compares names without case: yes"
}

# Stops when any entity of any kind already uses one of the names, in any spelling.
require_absent() { # name...
    local listings name
    listings="$("$C" list --all --format json 2>&1)" || fail "container list failed: $listings"
    listings+="$("$C" volume list --format json 2>&1)" || fail "container volume list failed"
    listings+="$("$C" machine list 2>&1)" || fail "container machine list failed"
    for name in "$@"; do
        if printf '%s' "$listings" | grep -qi -- "$name"; then
            fail "an existing entity matches '$name'; nothing was changed"
        fi
        if ls -a "$ROOT/containers" "$ROOT/volumes" "$ROOT/plugin-state/machine-apiserver/machines" 2>/dev/null |
            grep -qix -- "$name"; then
            fail "a directory named '$name' exists under $ROOT; nothing was changed"
        fi
    done
    say "no entity uses the names $*"
}

# Prints a file's SHA-256, or "absent".
digest() { [[ -f "$1" ]] && shasum -a 256 "$1" | cut -d' ' -f1 || echo absent; }

listing() { # directory
    printf '$ ls -la %q\n' "$1"
    ls -la "$1" 2>&1 | sed 's/^/    /'
}
