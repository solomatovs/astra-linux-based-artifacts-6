# Source artifacts (part 6) — cloudbeaver

This repository is a **git-only transport for build artifacts**: everything must be
retrievable with `git clone` alone (no GitHub Releases / LFS, which are served from
separate hosts that the build environment cannot reach).

It is the sixth artifact repository and carries everything needed to build the dmp
fork of CloudBeaver **without network access**:

| component | contents |
|-----------|----------|
| `cloudbeaver/src`  | source tarballs of the three forks, tag `dmp-26.1.3`, plus the yarn 4 cli |
| `cloudbeaver/deps` | build dependencies of that tag: maven local repository (with the tycho p2 cache) and the global yarn cache |

The consuming `Makefile`/`Dockerfile` live in the `cloudbeaver` fork itself
(`deploy/docker/cloudbeaver-dmp`), where `artifacts/` is git-ignored — only these
files need git transport.

Building also needs the base images `dmp/java:21`, `dmp/nodejs:22.22.1-dist` and
`dmp/gcc:12.4.0-dist` from
[`astra-linux-based`](https://github.com/solomatovs/astra-linux-based.git).

All artifacts are committed **into git**. To respect GitHub's hard
**100 MB-per-file** limit, files larger than that are split into
`<file>.part-000`, `<file>.part-001`, … and only the pieces are committed.
[`artifacts-manifest.tsv`](artifacts-manifest.tsv) lists every artifact with its
path, size, sha256, and part count (`parts=0` means stored whole).

## On the build machine

```bash
git clone https://github.com/solomatovs/astra-linux-based-artifacts-6.git
cd astra-linux-based-artifacts-6
./scripts/assemble-artifacts.sh   # rebuild split files + verify all sha256

CB=/path/to/cloudbeaver/deploy/docker/cloudbeaver-dmp
mkdir -p "$CB/artifacts/src" "$CB/artifacts/deps/26.1.3"
cp cloudbeaver/src/* "$CB/artifacts/src/"
tar -xzf cloudbeaver/deps/cloudbeaver-deps-26.1.3.tar.gz -C "$CB/artifacts/deps/26.1.3"

cd "$CB"
make all                          # sources are already in place, nothing is downloaded
```

`make sources` only fetches what is missing, so the copied tarballs stop it from
reaching GitHub. `make deps` — the only step that needs the internet — is **not**
run here: its result is exactly what `cloudbeaver/deps` carries. The build itself
runs with `--network=none` (maven with `-o -Dmaven.repo.local=`, yarn with
`enableNetwork=0`), so a missing dependency fails the build instead of silently
going online.

If maven/npm must go through an internal nexus, drop `artifacts/maven-settings.xml`
and `artifacts/yarnrc.yml` next to them (examples ship in the fork). They are not
needed for the flow above — everything already resolves from `artifacts/deps`.

The dev flow (`make all SOURCE=local`, sources taken from local working trees) needs
its own `artifacts/deps/local`; it is a developer-machine concern and is not carried
here.

## Publishing (maintainer, needs push access)

Large files make the total push exceed GitHub's ~2 GB single-push limit, so the
push is done in size-bounded batches:

```bash
./scripts/split-artifacts.sh      # (re)generate .part-* pieces + manifest for files >95 MB
./scripts/push-artifacts.sh       # commit + push in <1.2 GB batches
```

## Adding a new version

1. In the fork: `make deps VERSION=<версия>` (needs network), which fills
   `artifacts/deps/<версия>`.
2. Copy the source tarballs and the yarn cli from `artifacts/src` into
   `cloudbeaver/src/` here, and pack the dependencies:
   `tar -czf cloudbeaver/deps/cloudbeaver-deps-<версия>.tar.gz --sort=name -C <...>/artifacts/deps/<версия> .`
3. Run `./scripts/split-artifacts.sh`, then `./scripts/push-artifacts.sh`.

Override `BATCH_MB` (default 1200) to change push batch size. `split-artifacts.sh`
selects files by size rather than by extension, so any archive type is covered.
