# Manifest-driven multi-engine patch applier — design

**Date:** 2026-07-07
**Status:** Approved (design), pending implementation plan
**Repo:** apk-patch-kit

## Problem

Two maintained patch ecosystems exist in parallel — **ReVanced** (`app.revanced.patcher`, `.rvp` bundles, `revanced-cli`) and **Morphe** (`app.morphe.patcher` fork, `.mpp` bundles, `morphe-cli`) — plus many third-party source repos (Piko, x-shim, RVX/inotia00, …). Their bundles are **not cross-compatible**: a `.rvp` and a `.mpp` are jars built against different patcher base classes, so one CLI cannot run the other's bundle.

Re-authoring patches that upstream already ships is wasted work. The repo already consumes upstream bundles ad-hoc (strava pulls an upstream `.rvp`; twitter's working X build pulls Piko + x-shim `.mpp`), but each is a bespoke manual invocation. There is no declarative, reproducible record of "app X → these bundles, this engine, this version, this patch selection."

## Goal

Extend **this repo** (not a new manager app) so each app declares where its patches come from and how to apply them. The driver reads that manifest, fetches/builds the right bundles, dispatches to the correct engine CLI, signs, and repackages. Result:

- **Zero re-authored patches for covered apps** — pin upstream bundles instead.
- **Hand-written `patches/<app>/` only for uncovered apps** — then upstream them.
- **Reproducible builds** — engine, CLI version, bundle versions, and patch selection all captured in the manifest.

Explicit non-goals (YAGNI): no on-device manager, no GUI, no cross-engine patch merging, no auto-update daemon, no changes to how patches are authored.

## Environment facts (verified 2026-07-07)

- `python3` 3.11.2 — ships `tomllib` (stdlib TOML reader). No pip deps needed.
- `jq` 1.6 present.
- Host: Windows + WSL2; scripts call Windows `adb.exe` (existing `patch-apks.sh` machinery).
- `revanced-cli-*.jar` currently dropped manually at repo root; `morphe-cli` not yet wired in (the X build was a manual scratchpad invocation).
- `patch-apks.sh` is 715 lines, revanced-cli-only, with flags `--app/--apk/--patches/--cli/--no-ui/--package/--include-universal/--no-filter/--install/--reinstall/--adb/--sign-only/--maps-key` and a per-run PKCS12 keystore signing + split re-sign pipeline.

## Architecture

### 1. Per-app manifest — `apps/<app>/sources.toml`

Single front door for **all** apps (unified path; no separate handling for locally-authored patches).

Remote-consuming example (twitter — the proven X 12.2.0 recipe, serves as the reference):

```toml
package     = "com.twitter.android"
app_version = "12.2.0-release.0"
engine      = "morphe"                # "morphe" | "revanced"
apk         = "apks/x-12.2.0.apkm"    # relative to apps/<app>/; .apk | .apks | .apkm | .xapk

[[bundle]]                            # ordered list; ALL must share `engine`
type    = "github"                    # "github" | "gitlab" | "local"
repo    = "crimera/piko"
version = "3.7.0"
asset   = "patches-3.7.0.mpp"         # optional; default = sole *.mpp/*.rvp release asset
sha256  = "<hex>"                     # optional integrity pin

[[bundle]]
type    = "gitlab"
repo    = "inotia00/x-shim"
version = "1.7.0"
asset   = "patches-1.7.0.mpp"
sha256  = "<hex>"

[patches]                             # optional; omit entirely = all default-enabled patches
exclusive = false                     # if true, only `enable` patches run
enable    = []                        # patch names; empty = all default-enabled
disable   = []                        # patch names to force-off
```

Local-authored example (hidratespark):

```toml
package     = "hidratenow.com.hidrate.hidrateandroid"
app_version = "4.6.9"
engine      = "revanced"
apk         = "apks/base.apk"

[[bundle]]
type    = "local"
project = "hidratespark"              # → ./gradlew :patches:hidratespark:build, use patches/hidratespark/build/libs/*.jar
```

Field semantics:

- `engine` — which CLI applies every bundle. Per-app, single-valued.
- `apk` — input, relative to `apps/<app>/`. Passed to the CLI as-is (both CLIs merge `.apks`/`.apkm` split bundles internally).
- `[[bundle]]` — ordered array. `type=local` builds a repo subproject; `type=github|gitlab` fetches a pinned release asset. Order is preserved when assembling `--patches` args (matters for morphe: x-shim after piko).
- `[patches]` — optional selection. Absence means "all default-enabled." Maps to CLI `-e`/`-d`/`--exclusive`. Patch **option** passthrough (e.g. the existing `--maps-key`) is out of scope for v1; keep the current `--maps-key` flag working via the manual path.

### 2. Engine CLI management — `engines.toml` (repo root) + `bin/` (gitignored)

```toml
[revanced]
version = "<tag>"
# release source is fixed in code (GitLab ReVanced) — only version is pinned here
[morphe]
version = "1.9.1"
```

Driver ensures the required engine's CLI jar is present in `bin/` before applying; fetches + verifies on demand (same mechanism as bundles). Removes the manual "download revanced-cli into repo root" step. The legacy `--cli <jar>` flag still overrides for manual runs.

### 3. Bundle cache — `.cache/bundles/` (gitignored)

Fetched bundles keyed by `<host>_<repo-slug>_<version>_<asset>`. If the manifest pins `sha256`, verify after download and on cache hit; mismatch is a hard error. If no `sha256`, cache by key without verification (record the computed sha in driver output so the user can pin it). Network is touched only when a keyed artifact is absent.

### 4. Driver — refactor `patch-apks.sh`

Resolution order when run:

1. `--app <name>` (or interactive pick) → if `apps/<app>/sources.toml` exists, take the **manifest path**; else fall back to the **legacy path** (current auto-discovery of `patches/<app>/build/libs/*.jar` + `apks/`).
2. Explicit `--apk`/`--patches`/`--cli` always force the legacy manual path (override).

Manifest path steps:

1. Parse `sources.toml` (via `lib/manifest.sh`).
2. Validate: all `[[bundle]]` share `engine`; else error. `apk` exists. `engine ∈ {morphe, revanced}`.
3. Ensure engine CLI in `bin/` (`lib/fetch.sh`), pinned by `engines.toml`.
4. Resolve each bundle → local path: `local` builds the gradle subproject; `github`/`gitlab` fetch+cache.
5. Assemble engine args: repeated `--patches <path>`, plus `-e/-d/--exclusive` from `[patches]`.
6. Dispatch to `lib/engine-<engine>.sh` → runs the CLI → produces the patched APK/bundle.
7. Sign + repack (reuse existing stages) → `build/<app>-patched.{apk,apks}` → print `adb install(-multiple)` line.

New flag `--resolve-only`: run steps 1–5 and print the full plan (engine, CLI version, each bundle's resolved version + cache path, patch selection, and the exact CLI command) **without** executing. Cheap per-app manifest sanity check.

### 5. Components (isolated units)

| Unit | Responsibility | Depends on |
|------|----------------|------------|
| `lib/manifest.sh` | Parse one `sources.toml` → shell-consumable vars/JSON | `python3 -c tomllib` → JSON → `jq` |
| `lib/fetch.sh` | Resolve+download a GitHub/GitLab release asset (or engine CLI) → verified cache path | `curl`, `gh` (GitHub), GitLab REST, `sha256sum` |
| `lib/engine-morphe.sh` | Build the `morphe-cli patch` command line + run it | `bin/morphe-cli.jar`, `java` |
| `lib/engine-revanced.sh` | Build the `revanced-cli patch` command line + run it | `bin/revanced-cli.jar`, `java` |
| `patch-apks.sh` | Orchestrate: resolve app → manifest-or-legacy → sign → repack → install line | the libs above + existing signing/repack stages |

Signing/repack stages stay in `patch-apks.sh` unchanged: morphe-cli self-signs a single merged APK (verified working for X today); the revanced path keeps the per-run PKCS12 keystore + split re-sign.

### 6. Hard constraints

- **One engine per app.** Mixing `.rvp` and `.mpp` bundles in one invocation is impossible (incompatible patchers). Driver errors on mixed `engine`/bundle types.
- **Local bundles are revanced-engine.** All current `patches/<app>/` are `app.revanced.patcher`-based; a `type=local` bundle implies `engine=revanced`. Driver errors if a manifest pairs `type=local` with `engine=morphe`.

## Migration

Write `sources.toml` for all 7 existing apps (mechanical, from known packages/versions in each `apps/<app>/README.md`):

- **twitter** → the morphe piko@3.7.0 + x-shim@1.7.0 recipe against `apks/x-12.2.0.apkm` (reference example; note the 12.4.1 apks are retained but not the target).
- **strava** → revanced, remote upstream `.rvp` (currently a root-drop; becomes a pinned `[[bundle]]`).
- **hidratespark, meetup, tinder, metoffice, foldersync** → revanced, single `type=local` bundle pointing at their `patches/<app>` subproject.

## Testing

- `--resolve-only` on each app's manifest → assert the printed plan matches expectations (engine, versions, command). Primary cheap check.
- End-to-end smoke: twitter manifest reproduces today's working `build/x-12.2.0-patched.apk` (byte-identical dex not required; successful patch + install is the bar).
- One revanced local app (e.g. hidratespark) builds through the new manifest path and matches the legacy path output.
- Error cases: mixed engines; `type=local` + `engine=morphe`; missing `apk`; sha256 mismatch — each must fail loudly with a clear message.

## Open implementation details (resolved defaults, not blockers)

- **TOML→shell:** `python3 -c 'import tomllib,json,sys; json.dump(tomllib.load(open(sys.argv[1],"rb")),sys.stdout)'` then `jq` to extract. No third-party dep.
- **GitLab asset URLs:** release `assets.links[].url` (as used for x-shim today) or the project uploads path; GitHub via `gh api releases`.
- **sha recording:** on unpinned fetch, print `sha256=<hex>` so the user can paste it into the manifest to lock it.
