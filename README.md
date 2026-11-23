# Data-loss defects in apple/container: reproductions

This repository reproduces data-loss defects in [apple/container](https://github.com/apple/container)
with the original upstream code, and runs the same reproductions against branches that fix them.
The reproductions run in GitHub Actions on GitHub-hosted macOS runners. Each run shows every
command, its answer and the evidence (file listings, SHA-256 hashes, CLI output).

## Code under test

| Column | Code | Commit |
|---|---|---|
| `upstream-1.7.1` | release 1.7.1, the signed installer package from the [release page](https://github.com/apple/container/releases/tag/1.7.1) | `a15b46097aa4c2325da13c1fb5192b9274aab083` |
| `upstream-main` | `main`, built from source on the runner | `16e8d488ee1d9ede35ab9cf21b9973ffdc9361b3` (2026-11-13) |
| `fix-a` | branch [`fix/folded-name-create`](https://github.com/beshkenadze/container/tree/fix/folded-name-create), on `main` above | 5f19b9ee762a45f46ca79ee88cf593023077fc2b |
| `fix-b` | branch [`fix/keep-unloadable-bundles`](https://github.com/beshkenadze/container/tree/fix/keep-unloadable-bundles), on `main` above | e7c73275ed6d68c48ec40ec4182d67333d36d2d5 |
| `pr-2127` | head of [apple/container#2127](https://github.com/apple/container/pull/2127), another fix for defect B | 1cbab2b04ba474dd149437a477968f81b6af57ae |

The upstream code is not changed. The built columns use `make build installer-pkg` and install the
package with `installer`, as a release is installed.

## The defects

### A. Names that the file system folds

The data root of `container` is `~/Library/Application Support/com.apple.container`. On macOS it is
on a case-insensitive volume by default, so `web` and `WEB` name the same directory. The services
look up a volume, container or machine by its exact name, find nothing, and then create or write
`<root>/<kind>/<name>`. That path leads into the directory of the existing entity.

- **A1, volumes** ([`a1-volume-folded-name.sh`](repro/a1-volume-folded-name.sh)).
  `container volume create VDATA` beside an existing `vdata` formats the image of `vdata` again,
  then answers `entity VDATA already exist`. The files in `vdata` are gone.
- **A2, containers** ([`a2-container-folded-name.sh`](repro/a2-container-folded-name.sh)).
  `container create --name CWEB` beside `cweb` succeeds and writes its runtime configuration over
  that of `cweb`. `container delete CWEB` then removes the directory of `cweb`; `cweb` is still
  listed.
- **A3, machines** ([`a3-machine-folded-name.sh`](repro/a3-machine-folded-name.sh)).
  `container machine create --name MDEV` beside `mdev` writes into the bundle of `mdev`.

What CI shows for A2, and what it cannot show: a GitHub-hosted runner cannot boot a VM, so the
first container is created but never started. Its directory then holds only
`runtime-configuration.json`. CI shows that the create of the other name overwrites this file and
that the delete of the other name removes the directory. On a Mac where the first container has
run, the same directory also holds the container's root file system (`rootfs.ext4`, all data the
container wrote), and the delete removes it too. CI cannot show that part.

### B. A load error at startup deletes the container's directory

([`b-startup-load-error.sh`](repro/b-startup-load-error.sh))

When the API server starts, it loads every directory under `<root>/containers`. When a load throws,
the server deletes the directory. A load throws, for example, when the container's runtime plugin
is not installed at that moment, or when its configuration cannot be read. The script names a
runtime plugin that is not installed in the configuration of one throwaway container, which is the
state of a container whose plugin was removed, and restarts the system. Reported upstream as
[apple/container#2033](https://github.com/apple/container/issues/2033).

## Results

Run [45190044627](https://github.com/beshkenadze/apple-container-data-loss-repro/actions/runs/45190044627)
(GitHub-hosted runner `macos-26`, image `macos-26-arm64` 20261117, macOS 26.7.2, Xcode 26.6):

| Defect | upstream-1.7.1 | upstream-main | fix-a | fix-b | pr-2127 |
|---|---|---|---|---|---|
| A1 volume | DEFECT REPRODUCED | DEFECT REPRODUCED | NO DEFECT | — | — |
| A2 container | DEFECT REPRODUCED | DEFECT REPRODUCED | NO DEFECT | — | — |
| A3 machine | DEFECT REPRODUCED | DEFECT REPRODUCED | NO DEFECT | — | — |
| B startup load | DEFECT REPRODUCED | DEFECT REPRODUCED | — | NO DEFECT | NO DEFECT |

The same run also builds each fix branch and runs its new unit tests twice: with the fix they
pass, and with the sources of upstream `main` the service tests fail (jobs "unit tests of fix-a"
and "unit tests of fix-b"). The jobs "unit suite on ..." run the unit test suite of upstream
`main` and of both fix branches; one test that fails on upstream `main` on this runner
(`resourceFlagsAreSeparateFromWorkers`, an argument parser error) is skipped in all three. Each
reproduce job checks that the installed server reports the commit of its column.

## How a reader sees the result

The job summary of each run has a table: defect by code under test. Each cell is the last line of
the script, `DEFECT REPRODUCED` or `NO DEFECT`, and says whether that is the expected result. The
expectation is fixed per column: the upstream columns must reproduce the defect, the fix columns
must not. A result that differs from the expectation, or a script that cannot run to its end
(`ERROR`), fails the job.

## Run a reproduction on a Mac by hand

Requirements: `container` installed and started (`container system start`), the data root on the
default (case-insensitive) volume, and for A1 `debugfs` (`brew install e2fsprogs`).

```sh
git clone https://github.com/beshkenadze/apple-container-data-loss-repro
cd apple-container-data-loss-repro
repro/a1-volume-folded-name.sh
repro/a2-container-folded-name.sh
repro/a3-machine-folded-name.sh
REPRO_ALLOW_RESTART=1 repro/b-startup-load-error.sh
```

Read this before you run them:

- Each run makes new objects with a random suffix (for example `vfoldk3m9x2qa`). Before it makes
  anything, a script stops when any existing volume, container or machine matches one of its names
  in any case. At the end it removes only the objects that it made.
- The scripts pull `busybox:1.37-musl` (A2, B) and `alpine:3.22` (A3), and do not remove them.
- A1 writes one file into the image of the volume that it made, with `debugfs -w`.
- B edits the configuration of the container that it made, then **stops and starts the container
  system**. That stops every running container on the Mac. It runs only with
  `REPRO_ALLOW_RESTART=1`, and only when the system uses the default data root.
- Exit status: 1 with `DEFECT REPRODUCED`, 0 with `NO DEFECT`, 2 when the script could not run to
  its end.

## Not included

- **A stale delete.** `delete` reads the container's state before it takes the service lock and,
  under the lock, removes whatever container has the name. When the old container is deleted and a
  new one is created while a second delete waits, the second delete removes the new one; but the
  second delete was sent after the create, so this is a valid order of the three requests and not
  a defect. A delete without `--force` cannot reach a running replacement, because the
  replacement's start must wait behind the queued delete.
  Unverified risk, related to [apple/container#2116](https://github.com/apple/container/issues/2116):
  `delete --force` stops a running container outside the lock and then removes the container that
  holds the name. If, during that stop, the old container is removed and a new one runs under the
  same name, the force delete can remove the new container's directory without stopping it. This
  needs a VM and a narrow timing window; it is not reproduced here.
- **Anything that needs a running container.** GitHub-hosted macOS runners cannot boot a VM:
  `Error Domain=VZErrorDomain Code=2 "Virtualization is not available on this hardware."`. A
  reproduction that needs a started container needs a self-hosted Mac.
