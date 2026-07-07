# Manifest-driven multi-engine patch applier — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let each app declare its patch sources in `apps/<app>/sources.toml`; the driver fetches/builds the right bundles, dispatches to `revanced-cli` or `morphe-cli`, signs, and repackages — so covered apps consume upstream bundles instead of re-authored patches.

**Architecture:** Small bash libs under `lib/` do one job each (parse manifest, fetch+cache release assets, build per-engine CLI args). `patch-apks.sh` gains a manifest resolution path that falls back to today's legacy flags. Pure logic (parse, validate, cache-key, arg-assembly) is TDD'd with fixtures; network/CLI/device steps are smoke-verified.

**Tech Stack:** bash, `python3` 3.11 `tomllib` (stdlib), `jq` 1.6, `curl`, `gh`, `java` 17. No new dependencies.

## Global Constraints

- No new runtime dependencies — only `python3`/`jq`/`curl`/`gh`/`java`, all already present. Copied verbatim from spec: "No pip deps needed."
- One engine per app: mixing `.rvp` + `.mpp` in one invocation is impossible. Driver must error on mixed engine/bundle types.
- `type=local` bundle implies `engine=revanced` (all `patches/<app>/` are `app.revanced.patcher`-based). Driver must error on `type=local` + `engine=morphe`.
- Bundles/CLIs/caches are gitignored: `bin/`, `.cache/bundles/`. Never commit binaries.
- Existing legacy flags (`--apk/--patches/--cli/--no-ui/--package/--install/--reinstall/--sign-only/--maps-key/--adb`) must keep working unchanged; the manifest path is additive.
- `engine ∈ {morphe, revanced}` exactly.
- Manifest scope is unified: every app gets a `sources.toml`, including local-patch apps (via a `type=local` bundle).

---

## File Structure

- Create `tests/lib.sh` — dependency-free assert helpers + runner.
- Create `tests/fixtures/*.toml` — manifest fixtures for tests.
- Create `tests/test_*.sh` — one test file per lib unit.
- Create `lib/manifest.sh` — parse + validate `sources.toml`.
- Create `lib/fetch.sh` — cache-key + release-asset download/verify.
- Create `lib/engine-revanced.sh` — build `revanced-cli patch` arg list.
- Create `lib/engine-morphe.sh` — build `morphe-cli patch` arg list.
- Create `engines.toml` — pinned engine CLI versions.
- Modify `patch-apks.sh` — manifest resolution path + `--resolve-only`.
- Modify `.gitignore` — add `bin/`, `.cache/`.
- Create `apps/<app>/sources.toml` × 7 — migration.
- Modify `CLAUDE.md` — document the manifest flow.

---

## Task 1: Test harness + manifest parse

**Files:**
- Create: `tests/lib.sh`
- Create: `tests/fixtures/twitter.toml`, `tests/fixtures/hidratespark.toml`
- Create: `lib/manifest.sh`
- Test: `tests/test_manifest.sh`

**Interfaces:**
- Produces: `manifest_to_json <toml> -> JSON on stdout`; `manifest_get <toml> <jq-filter> -> string`.
- Produces (harness): `assert_eq actual expected msg`, `assert_contains haystack needle msg`, `assert_nonzero cmd...`, `t_summary` (returns nonzero if any fail).

- [ ] **Step 1: Write the test harness**

Create `tests/lib.sh`:
```bash
#!/usr/bin/env bash
# Dependency-free assert helpers. Source this in tests/test_*.sh.
_t_pass=0; _t_fail=0
assert_eq() { # actual expected msg
  if [ "$1" = "$2" ]; then _t_pass=$((_t_pass+1)); else
    _t_fail=$((_t_fail+1)); printf 'FAIL: %s\n  expected: %s\n  actual:   %s\n' "$3" "$2" "$1"; fi
}
assert_contains() { # haystack needle msg
  case "$1" in *"$2"*) _t_pass=$((_t_pass+1)) ;;
  *) _t_fail=$((_t_fail+1)); printf 'FAIL: %s (missing: %s)\n' "$3" "$2" ;; esac
}
assert_nonzero() { # cmd... (expects nonzero exit)
  if "$@" >/dev/null 2>&1; then _t_fail=$((_t_fail+1)); printf 'FAIL: expected nonzero: %s\n' "$*"
  else _t_pass=$((_t_pass+1)); fi
}
t_summary() { printf 'pass=%d fail=%d\n' "$_t_pass" "$_t_fail"; [ "$_t_fail" -eq 0 ]; }
```

- [ ] **Step 2: Write the fixtures**

Create `tests/fixtures/twitter.toml`:
```toml
package     = "com.twitter.android"
app_version = "12.2.0-release.0"
engine      = "morphe"
apk         = "apks/x-12.2.0.apkm"

[[bundle]]
type = "github"
repo = "crimera/piko"
version = "3.7.0"

[[bundle]]
type = "gitlab"
repo = "inotia00/x-shim"
version = "1.7.0"

[patches]
exclusive = false
```

Create `tests/fixtures/hidratespark.toml`:
```toml
package     = "hidratenow.com.hidrate.hidrateandroid"
app_version = "4.6.9"
engine      = "revanced"
apk         = "apks/base.apk"

[[bundle]]
type = "local"
project = "hidratespark"
```

- [ ] **Step 3: Write the failing test**

Create `tests/test_manifest.sh`:
```bash
#!/usr/bin/env bash
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$HERE/.." && pwd)"
. "$HERE/lib.sh"; . "$ROOT/lib/manifest.sh"
FX="$HERE/fixtures"

assert_eq "$(manifest_get "$FX/twitter.toml" '.engine')" "morphe" "twitter engine"
assert_eq "$(manifest_get "$FX/twitter.toml" '.package')" "com.twitter.android" "twitter package"
assert_eq "$(manifest_get "$FX/twitter.toml" '.bundle | length')" "2" "twitter bundle count"
assert_eq "$(manifest_get "$FX/twitter.toml" '.bundle[0].repo')" "crimera/piko" "twitter bundle0 repo"
assert_eq "$(manifest_get "$FX/hidratespark.toml" '.bundle[0].type')" "local" "hs bundle type"
t_summary
```

- [ ] **Step 4: Run test to verify it fails**

Run: `bash tests/test_manifest.sh`
Expected: FAIL — `lib/manifest.sh` does not exist (source error / `manifest_get: command not found`).

- [ ] **Step 5: Write minimal implementation**

Create `lib/manifest.sh`:
```bash
#!/usr/bin/env bash
# Parse apps/<app>/sources.toml. Requires python3 (tomllib) + jq.

manifest_to_json() { # <toml-file> -> JSON on stdout; nonzero on invalid TOML
  python3 -c 'import tomllib,json,sys
json.dump(tomllib.load(open(sys.argv[1],"rb")),sys.stdout)' "$1"
}

manifest_get() { # <toml-file> <jq-filter> -> string ("" if null/absent)
  manifest_to_json "$1" | jq -r "$2 // empty"
}
```

- [ ] **Step 6: Run test to verify it passes**

Run: `bash tests/test_manifest.sh`
Expected: `pass=5 fail=0`

- [ ] **Step 7: Commit**

```bash
git add tests/lib.sh tests/fixtures/twitter.toml tests/fixtures/hidratespark.toml tests/test_manifest.sh lib/manifest.sh
git commit -m "feat(manifest): sources.toml parser + bash test harness"
```

---

## Task 2: Manifest validation

**Files:**
- Modify: `lib/manifest.sh` (add `manifest_validate`)
- Create: `tests/fixtures/bad-engine.toml`, `tests/fixtures/bad-local-morphe.toml`, `tests/fixtures/bad-nobundle.toml`
- Test: `tests/test_manifest.sh` (extend)

**Interfaces:**
- Consumes: `manifest_to_json` from Task 1.
- Produces: `manifest_validate <toml> -> 0 if valid, nonzero + stderr message otherwise`.

- [ ] **Step 1: Write the bad fixtures**

Create `tests/fixtures/bad-engine.toml`:
```toml
package = "x"; app_version = "1"; engine = "banana"; apk = "a.apk"
[[bundle]]
type = "github"; repo = "a/b"; version = "1"
```
Create `tests/fixtures/bad-local-morphe.toml`:
```toml
package = "x"; app_version = "1"; engine = "morphe"; apk = "a.apk"
[[bundle]]
type = "local"; project = "x"
```
Create `tests/fixtures/bad-nobundle.toml`:
```toml
package = "x"; app_version = "1"; engine = "revanced"; apk = "a.apk"
```

- [ ] **Step 2: Write the failing test (append to `tests/test_manifest.sh` before `t_summary`)**

```bash
assert_eq "$(manifest_validate "$FX/twitter.toml" >/dev/null 2>&1; echo $?)" "0" "twitter valid"
assert_eq "$(manifest_validate "$FX/hidratespark.toml" >/dev/null 2>&1; echo $?)" "0" "hs valid"
assert_nonzero manifest_validate "$FX/bad-engine.toml"
assert_nonzero manifest_validate "$FX/bad-local-morphe.toml"
assert_nonzero manifest_validate "$FX/bad-nobundle.toml"
```

- [ ] **Step 3: Run test to verify it fails**

Run: `bash tests/test_manifest.sh`
Expected: FAIL — `manifest_validate: command not found`.

- [ ] **Step 4: Write minimal implementation (append to `lib/manifest.sh`)**

```bash
manifest_validate() { # <toml-file> -> 0 valid; nonzero + stderr on error
  local f="$1" json engine
  json="$(manifest_to_json "$f" 2>/dev/null)" || { echo "manifest: invalid TOML: $f" >&2; return 1; }
  engine="$(printf '%s' "$json" | jq -r '.engine // empty')"
  case "$engine" in morphe|revanced) ;; *) echo "manifest: engine must be morphe|revanced (got '$engine')" >&2; return 1 ;; esac
  [ "$(printf '%s' "$json" | jq '(.bundle // []) | length')" -ge 1 ] || { echo "manifest: need >=1 [[bundle]]" >&2; return 1; }
  if printf '%s' "$json" | jq -e '.bundle[] | select((.type // "") as $t | ($t|IN("github","gitlab","local"))|not)' >/dev/null; then
    echo "manifest: bundle.type must be github|gitlab|local" >&2; return 1; fi
  if printf '%s' "$json" | jq -e '.bundle[] | select(.type=="local")' >/dev/null && [ "$engine" != revanced ]; then
    echo "manifest: type=local requires engine=revanced" >&2; return 1; fi
  return 0
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `bash tests/test_manifest.sh`
Expected: `pass=10 fail=0`

- [ ] **Step 6: Commit**

```bash
git add lib/manifest.sh tests/test_manifest.sh tests/fixtures/bad-*.toml
git commit -m "feat(manifest): validate engine, bundle types, local⇒revanced rule"
```

---

## Task 3: Fetch cache-key + URL resolution (pure)

**Files:**
- Create: `lib/fetch.sh`
- Test: `tests/test_fetch.sh`

**Interfaces:**
- Produces: `fetch_cache_key <host> <repo> <version> <asset> -> string`.
- Produces: `fetch_gitlab_project_id <repo> -> url-encoded project path` (e.g. `inotia00%2Fx-shim`).
- Produces (Task 4/7 rely on): `fetch_asset <host> <repo> <version> <asset> <sha256|-> -> prints cached file path` (network; not unit-tested here).

- [ ] **Step 1: Write the failing test**

Create `tests/test_fetch.sh`:
```bash
#!/usr/bin/env bash
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$HERE/.." && pwd)"
. "$HERE/lib.sh"; . "$ROOT/lib/fetch.sh"

assert_eq "$(fetch_cache_key github crimera/piko 3.7.0 patches-3.7.0.mpp)" \
  "github_crimera-piko_3.7.0_patches-3.7.0.mpp" "cache key"
assert_eq "$(fetch_gitlab_project_id inotia00/x-shim)" "inotia00%2Fx-shim" "gitlab project id"
t_summary
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test_fetch.sh`
Expected: FAIL — `lib/fetch.sh` missing.

- [ ] **Step 3: Write minimal implementation**

Create `lib/fetch.sh`:
```bash
#!/usr/bin/env bash
# Resolve + download GitHub/GitLab release assets into a verified local cache.
FETCH_CACHE="${FETCH_CACHE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/.cache/bundles}"

fetch_cache_key() { # host repo version asset
  printf '%s_%s_%s_%s' "$1" "$(printf '%s' "$2" | tr '/' '-')" "$3" "$4"
}

fetch_gitlab_project_id() { # repo (group/name) -> URL-encoded path
  printf '%s' "$1" | sed 's#/#%2F#g'
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test_fetch.sh`
Expected: `pass=2 fail=0`

- [ ] **Step 5: Add the download wrapper (no unit test — network)**

Append to `lib/fetch.sh`:
```bash
# fetch_asset host repo version asset sha256|- -> prints cached path; downloads if absent.
fetch_asset() {
  local host="$1" repo="$2" ver="$3" asset="$4" sha="$5"
  mkdir -p "$FETCH_CACHE"
  local key path url; key="$(fetch_cache_key "$host" "$repo" "$ver" "$asset")"; path="$FETCH_CACHE/$key"
  if [ ! -f "$path" ]; then
    case "$host" in
      github) url="$(gh api "repos/$repo/releases/tags/$ver" \
                 --jq ".assets[]|select(.name==\"$asset\")|.browser_download_url")" ;;
      gitlab) url="$(curl -s "https://gitlab.com/api/v4/projects/$(fetch_gitlab_project_id "$repo")/releases/$ver" \
                 | jq -r ".assets.links[]|select(.name==\"$asset\")|.url")" ;;
      *) echo "fetch: unknown host $host" >&2; return 1 ;;
    esac
    [ -n "$url" ] && [ "$url" != null ] || { echo "fetch: asset not found: $host $repo $ver $asset" >&2; return 1; }
    curl -sL -o "$path" "$url" || { rm -f "$path"; echo "fetch: download failed: $url" >&2; return 1; }
  fi
  if [ "$sha" != "-" ]; then
    local got; got="$(sha256sum "$path" | cut -d' ' -f1)"
    [ "$got" = "$sha" ] || { echo "fetch: sha256 mismatch for $key (got $got want $sha)" >&2; return 1; }
  else
    echo "fetch: $key sha256=$(sha256sum "$path" | cut -d' ' -f1) (pin this in sources.toml)" >&2
  fi
  printf '%s' "$path"
}
```

- [ ] **Step 6: Commit**

```bash
git add lib/fetch.sh tests/test_fetch.sh
git commit -m "feat(fetch): cache-key/url resolution + release-asset download+verify"
```

---

## Task 4: Engine CLI management (`engines.toml` + `bin/`)

**Files:**
- Create: `engines.toml`
- Modify: `lib/fetch.sh` (add `fetch_engine_cli`)
- Modify: `.gitignore`
- Test: `tests/test_fetch.sh` (extend, pure part only)

**Interfaces:**
- Consumes: `fetch_asset` (Task 3).
- Produces: `engine_cli_path <engine> -> prints bin/<engine>-cli.jar, fetching if absent`.

- [ ] **Step 1: Write `engines.toml`**

Create `engines.toml` (fill `revanced.version` during migration; morphe is known-good):
```toml
[revanced]
version = "TBD-at-migration"   # replaced with a real revanced-cli tag in Task 8

[morphe]
version = "1.9.1"
```

- [ ] **Step 2: Extend `.gitignore`**

Append to `.gitignore`:
```
bin/
.cache/
```

- [ ] **Step 3: Write the failing test (append to `tests/test_fetch.sh` before `t_summary`)**

```bash
assert_eq "$(ENGINES_TOML="$HERE/fixtures/engines.toml" engine_cli_key morphe)" "morphe-cli.jar" "cli key morphe"
```
Create `tests/fixtures/engines.toml`:
```toml
[revanced]
version = "5.0.0"
[morphe]
version = "1.9.1"
```

- [ ] **Step 4: Run test to verify it fails**

Run: `bash tests/test_fetch.sh`
Expected: FAIL — `engine_cli_key: command not found`.

- [ ] **Step 5: Write minimal implementation (append to `lib/fetch.sh`)**

```bash
ENGINES_TOML="${ENGINES_TOML:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/engines.toml}"
BIN_DIR="${BIN_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin}"

engine_cli_key() { printf '%s-cli.jar' "$1"; }   # morphe -> morphe-cli.jar

engine_cli_path() { # engine (morphe|revanced) -> path to jar in bin/, fetching if absent
  local engine="$1" ver dst
  ver="$(python3 -c 'import tomllib,sys;print(tomllib.load(open(sys.argv[1],"rb"))[sys.argv[2]]["version"])' "$ENGINES_TOML" "$engine")" \
    || { echo "engine: no version pinned for $engine in $ENGINES_TOML" >&2; return 1; }
  mkdir -p "$BIN_DIR"; dst="$BIN_DIR/$(engine_cli_key "$engine")"
  if [ ! -f "$dst" ]; then
    local src
    case "$engine" in
      morphe)   src="$(fetch_asset github MorpheApp/morphe-cli "v$ver" "morphe-cli-$ver-all.jar" -)" ;;
      revanced) src="$(fetch_asset github ReVanced/revanced-cli "v$ver" "revanced-cli-$ver-all.jar" -)" ;;
      *) echo "engine: unknown engine $engine" >&2; return 1 ;;
    esac || return 1
    cp "$src" "$dst"
  fi
  printf '%s' "$dst"
}
```
Note: `revanced-cli` releases live on GitLab post-DMCA; if the GitHub mirror 404s at migration, switch the `revanced)` line to a `gitlab` fetch with the ReVanced GitLab project. Verified during Task 8.

- [ ] **Step 6: Run test to verify it passes**

Run: `bash tests/test_fetch.sh`
Expected: `pass=3 fail=0`

- [ ] **Step 7: Commit**

```bash
git add engines.toml .gitignore lib/fetch.sh tests/test_fetch.sh tests/fixtures/engines.toml
git commit -m "feat(engines): pin + auto-fetch engine CLI jars into bin/"
```

---

## Task 5: Per-engine argument assembly (pure)

**Files:**
- Create: `lib/engine-morphe.sh`, `lib/engine-revanced.sh`
- Test: `tests/test_engine.sh`

**Interfaces:**
- Consumes: manifest JSON (`manifest_to_json`), a newline-list of resolved bundle paths (in `[[bundle]]` order).
- Produces: `engine_<engine>_args <json> <cli_jar> <apk> <out> <bundles_file> -> prints one CLI arg per line` (excludes `java -jar`). Caller does `mapfile -t args < <(...)`.

- [ ] **Step 1: Write the failing test**

Create `tests/test_engine.sh`:
```bash
#!/usr/bin/env bash
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$HERE/.." && pwd)"
. "$HERE/lib.sh"; . "$ROOT/lib/manifest.sh"
. "$ROOT/lib/engine-morphe.sh"; . "$ROOT/lib/engine-revanced.sh"
FX="$HERE/fixtures"

BF="$(mktemp)"; printf '/c/piko.mpp\n/c/xshim.mpp\n' > "$BF"
J="$(manifest_to_json "$FX/twitter.toml")"
OUT="$(engine_morphe_args "$J" /bin/morphe-cli.jar in.apkm out.apk "$BF" | tr '\n' ' ')"
assert_contains "$OUT" "patch" "morphe subcommand"
assert_contains "$OUT" "--patches=/c/piko.mpp" "morphe bundle0"
assert_contains "$OUT" "--patches=/c/xshim.mpp" "morphe bundle1"
assert_contains "$OUT" "-o out.apk" "morphe output"
assert_contains "$OUT" "in.apkm" "morphe input"

BF2="$(mktemp)"; printf '/c/hs.rvp\n' > "$BF2"
JH="$(manifest_to_json "$FX/hidratespark.toml")"
OUTH="$(engine_revanced_args "$JH" /bin/revanced-cli.jar base.apk out2.apk "$BF2" | tr '\n' ' ')"
assert_contains "$OUTH" "patch" "revanced subcommand"
assert_contains "$OUTH" "-p /c/hs.rvp" "revanced bundle"
assert_contains "$OUTH" "base.apk" "revanced input"
rm -f "$BF" "$BF2"
t_summary
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test_engine.sh`
Expected: FAIL — engine arg functions undefined.

- [ ] **Step 3: Write minimal implementations**

Create `lib/engine-morphe.sh` (defines the shared `_engine_selection_lines`; `engine-revanced.sh` sources it):
```bash
#!/usr/bin/env bash
# Build a morphe-cli `patch` argument list (one arg per line, excl. `java -jar`).

# Shared: emit -e/-d/--exclusive lines from [patches]. Morphe + revanced use identical flags.
# jq emits "-e\nNAME" per enabled patch so each token lands on its own line.
_engine_selection_lines() { # json -> lines
  local json="$1"
  printf '%s' "$json" | jq -r '
    ((.patches.enable  // []) | map("-e\n\(.)")) +
    ((.patches.disable // []) | map("-d\n\(.)")) +
    (if (.patches.exclusive // false) then ["--exclusive"] else [] end)
    | .[]'
}

# Args: json cli_jar apk out bundles_file
engine_morphe_args() {
  local json="$1" cli="$2" apk="$3" out="$4" bf="$5"
  printf '%s\n' -jar "$cli" patch
  local b; while IFS= read -r b; do [ -n "$b" ] && printf -- '--patches=%s\n' "$b"; done < "$bf"
  printf '%s\n' --purge -o "$out"
  _engine_selection_lines "$json"
  printf '%s\n' "$apk"
}
```

Create `lib/engine-revanced.sh`:
```bash
#!/usr/bin/env bash
# Build a revanced-cli `patch` argument list (one arg per line, excl. `java -jar`).
# Requires _engine_selection_lines from engine-morphe.sh.
[ "$(type -t _engine_selection_lines)" = function ] || . "$(dirname "${BASH_SOURCE[0]}")/engine-morphe.sh"
engine_revanced_args() {
  local json="$1" cli="$2" apk="$3" out="$4" bf="$5"
  printf '%s\n' -jar "$cli" patch
  local b; while IFS= read -r b; do [ -n "$b" ] && printf '%s\n' -p "$b"; done < "$bf"
  printf '%s\n' -o "$out"
  _engine_selection_lines "$json"
  printf '%s\n' "$apk"
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test_engine.sh`
Expected: `pass=8 fail=0`

- [ ] **Step 5: Add a patch-selection test**

Create `tests/fixtures/select.toml`:
```toml
package="x"; app_version="1"; engine="morphe"; apk="a.apkm"
[[bundle]]
type="github"; repo="a/b"; version="1"
[patches]
exclusive=true
enable=["Remove Ads","Show sensitive media"]
disable=["Custom font"]
```
Append to `tests/test_engine.sh` before `t_summary`:
```bash
BF3="$(mktemp)"; printf '/c/b.mpp\n' > "$BF3"
JS="$(manifest_to_json "$FX/select.toml")"
SEL="$(engine_morphe_args "$JS" cli.jar a.apkm o.apk "$BF3" | tr '\n' '|')"
assert_contains "$SEL" "-e|Remove Ads" "enable pair"
assert_contains "$SEL" "-d|Custom font" "disable pair"
assert_contains "$SEL" "--exclusive" "exclusive flag"
rm -f "$BF3"
```

- [ ] **Step 6: Run test to verify it passes**

Run: `bash tests/test_engine.sh`
Expected: `pass=11 fail=0`

- [ ] **Step 7: Commit**

```bash
git add lib/engine-morphe.sh lib/engine-revanced.sh tests/test_engine.sh tests/fixtures/select.toml
git commit -m "feat(engine): per-engine CLI arg assembly + patch selection"
```

---

## Task 6: Bundle resolution (local build + remote fetch)

**Files:**
- Create: `lib/resolve.sh`
- Test: `tests/test_resolve.sh` (pure ordering only; network/gradle smoke manual)

**Interfaces:**
- Consumes: `fetch_asset` (Task 3), manifest JSON.
- Produces: `resolve_bundles <json> <app_dir> <out_bundles_file> -> writes resolved paths (one per line, in [[bundle]] order); nonzero on failure`.

- [ ] **Step 1: Write the failing test (pure: local paths, no network)**

Create `tests/fixtures/local-only.toml`:
```toml
package="x"; app_version="1"; engine="revanced"; apk="apks/base.apk"
[[bundle]]
type="local"; project="demoapp"
```
Create `tests/test_resolve.sh`:
```bash
#!/usr/bin/env bash
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$HERE/.." && pwd)"
. "$HERE/lib.sh"; . "$ROOT/lib/manifest.sh"; . "$ROOT/lib/fetch.sh"; . "$ROOT/lib/resolve.sh"

# Stub the local builder + gradle so the test is pure.
resolve_local_jar() { printf '%s' "/fake/${1}-patches.jar"; }
J="$(manifest_to_json "$HERE/fixtures/local-only.toml")"
OUTF="$(mktemp)"
resolve_bundles "$J" /fake/appdir "$OUTF"
assert_eq "$(cat "$OUTF")" "/fake/demoapp-patches.jar" "local resolves to built jar"
rm -f "$OUTF"
t_summary
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test_resolve.sh`
Expected: FAIL — `resolve_bundles: command not found`.

- [ ] **Step 3: Write minimal implementation**

Create `lib/resolve.sh`:
```bash
#!/usr/bin/env bash
# Resolve every [[bundle]] to a local file path, preserving order.
# resolve_local_jar <project> -> path (overridable in tests); default builds via gradle.
resolve_local_jar() { # project
  local proj="$1" root; root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  ( cd "$root" && ./gradlew ":patches:$proj:build" -q ) 1>&2 || return 1
  local jar; jar="$(ls -t "$root/patches/$proj/build/libs/"*.jar 2>/dev/null | head -1)"
  [ -n "$jar" ] || { echo "resolve: no jar built for $proj" >&2; return 1; }
  printf '%s' "$jar"
}

resolve_bundles() { # json app_dir out_file
  local json="$1" out="$3"; : > "$out"
  local n i type; n="$(printf '%s' "$json" | jq '.bundle | length')"
  for ((i=0; i<n; i++)); do
    type="$(printf '%s' "$json" | jq -r ".bundle[$i].type")"
    case "$type" in
      local)
        local proj; proj="$(printf '%s' "$json" | jq -r ".bundle[$i].project")"
        resolve_local_jar "$proj" >> "$out" || return 1; echo >> "$out" ;;
      github|gitlab)
        local repo ver asset sha
        repo="$(printf '%s' "$json" | jq -r ".bundle[$i].repo")"
        ver="$(printf '%s' "$json" | jq -r ".bundle[$i].version")"
        asset="$(printf '%s' "$json" | jq -r ".bundle[$i].asset // empty")"
        sha="$(printf '%s' "$json" | jq -r ".bundle[$i].sha256 // \"-\"")"
        [ -n "$asset" ] || asset="$(_resolve_default_asset "$type" "$repo" "$ver")" || return 1
        fetch_asset "$type" "$repo" "$ver" "$asset" "$sha" >> "$out" || return 1; echo >> "$out" ;;
      *) echo "resolve: bad bundle type $type" >&2; return 1 ;;
    esac
  done
}

_resolve_default_asset() { # type repo ver -> first *.mpp/*.rvp asset name
  local type="$1" repo="$2" ver="$3" name
  case "$type" in
    github) name="$(gh api "repos/$repo/releases/tags/$ver" --jq '.assets[].name' | grep -Ei '\.(mpp|rvp)$' | head -1)" ;;
    gitlab) name="$(curl -s "https://gitlab.com/api/v4/projects/$(fetch_gitlab_project_id "$repo")/releases/$ver" | jq -r '.assets.links[].name' | grep -Ei '\.(mpp|rvp)$' | head -1)" ;;
  esac
  [ -n "$name" ] || { echo "resolve: no .mpp/.rvp asset in $repo $ver" >&2; return 1; }
  printf '%s' "$name"
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test_resolve.sh`
Expected: `pass=1 fail=0`

- [ ] **Step 5: Commit**

```bash
git add lib/resolve.sh tests/test_resolve.sh tests/fixtures/local-only.toml
git commit -m "feat(resolve): order-preserving local-build + remote-fetch bundle resolution"
```

---

## Task 7: Driver integration + `--resolve-only`

**Files:**
- Modify: `patch-apks.sh` (add manifest path, `--resolve-only`, source libs)
- Test: manual `--resolve-only` smoke (network for remote; gradle for local)

**Interfaces:**
- Consumes: all `lib/*.sh`.
- Produces: manifest-driven run + a `--resolve-only` plan printer.

- [ ] **Step 1: Source the libs (add near top of `patch-apks.sh`, after existing setup)**

```bash
_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib"
. "$_LIB/manifest.sh"; . "$_LIB/fetch.sh"; . "$_LIB/resolve.sh"
. "$_LIB/engine-morphe.sh"; . "$_LIB/engine-revanced.sh"
```

- [ ] **Step 2: Add the `--resolve-only` flag to the arg parser**

In the `case "$1" in` block add:
```bash
        --resolve-only)      RESOLVE_ONLY=true; shift ;;
```
and initialise `RESOLVE_ONLY=false` with the other defaults.

- [ ] **Step 3: Add the manifest resolution branch**

After `--app` is known and before the legacy jar/apk auto-discovery, insert:
```bash
MANIFEST=""
if [ -n "${APP:-}" ] && [ -z "${APK_FILE:-}" ] && [ -z "${PATCHES_JAR:-}" ]; then
  cand="apps/$APP/sources.toml"
  [ -f "$cand" ] && MANIFEST="$cand"
fi

if [ -n "$MANIFEST" ]; then
  manifest_validate "$MANIFEST" || exit 1
  JSON="$(manifest_to_json "$MANIFEST")"
  ENGINE="$(printf '%s' "$JSON" | jq -r '.engine')"
  APKREL="$(printf '%s' "$JSON" | jq -r '.apk')"
  APP_DIR="apps/$APP"; APK_IN="$APP_DIR/$APKREL"
  [ -f "$APK_IN" ] || err "manifest apk not found: $APK_IN"
  CLI_JAR="$(engine_cli_path "$ENGINE")" || exit 1
  BUNDLES_FILE="$(mktemp)"
  resolve_bundles "$JSON" "$APP_DIR" "$BUNDLES_FILE" || exit 1
  OUT_APK="build/${APP}-patched.apk"; mkdir -p build
  mapfile -t CLI_ARGS < <(engine_"${ENGINE}"_args "$JSON" "$CLI_JAR" "$APK_IN" "$OUT_APK" "$BUNDLES_FILE")
  if [ "${RESOLVE_ONLY:-false}" = true ]; then
    echo "app:     $APP"; echo "engine:  $ENGINE"; echo "cli:     $CLI_JAR"; echo "input:   $APK_IN"
    echo "bundles:"; sed 's/^/  /' "$BUNDLES_FILE"
    echo "command: java ${CLI_ARGS[*]}"
    rm -f "$BUNDLES_FILE"; exit 0
  fi
  java "${CLI_ARGS[@]}" || err "patching failed"
  rm -f "$BUNDLES_FILE"
  echo "Patched → $OUT_APK"
  echo "Install: \"\$ADB\" install \"$(wslpath -w "$PWD/$OUT_APK" 2>/dev/null || echo "$PWD/$OUT_APK")\""
  exit 0
fi
# --- legacy path continues below unchanged ---
```
Note: morphe-cli self-signs the merged APK; the revanced path via a remote `.rvp` also self-signs. For local `.rvp`/revanced apps that previously relied on the script's per-run keystore + split re-sign, keep using the **legacy path** (don't add a manifest for those in Task 8 if they need the split-signing pipeline — see Task 8 decision).

- [ ] **Step 4: Smoke-test `--resolve-only` (local app, no network beyond gradle)**

Run: `./patch-apks.sh --app hidratespark --resolve-only` (after Task 8 writes its manifest — run this in Task 8).
Expected: prints engine=revanced, a built `*-patches.jar` bundle path, and a `java -jar … patch … base.apk` command. No patching performed.

- [ ] **Step 5: Commit**

```bash
git add patch-apks.sh
git commit -m "feat(driver): manifest resolution path + --resolve-only plan printer"
```

---

## Task 7b: `url` bundle type

Rationale: strava's `.rvp` is served from `https://api.revanced.app/v5/patches.rvp` (a plain URL, not a GitHub/GitLab release asset). Add a `url` bundle type so such prebuilt bundles can be pinned + fetched + cached like the others.

**Files:**
- Modify: `lib/fetch.sh` (add `fetch_url_key`, `fetch_url`)
- Modify: `lib/manifest.sh` (allow `url` in the bundle-type validation set)
- Modify: `lib/resolve.sh` (add `url)` case)
- Test: `tests/test_fetch.sh` (pure key), `tests/test_manifest.sh` (url is a valid type)

**Interfaces:**
- Produces: `fetch_url_key <url> -> stable cache-key string`; `fetch_url <url> <sha256|-> -> cached path` (network, no unit test).

- [ ] **Step 1: Failing test for `fetch_url_key` (append to `tests/test_fetch.sh` before `t_summary`)**

```bash
assert_eq "$(fetch_url_key https://api.revanced.app/v5/patches.rvp)" \
  "url_$(printf %s https://api.revanced.app/v5/patches.rvp | sha256sum | cut -c1-16)_patches.rvp" "url key"
```

- [ ] **Step 2: Run → fails** (`fetch_url_key: command not found`). `bash tests/test_fetch.sh`.

- [ ] **Step 3: Implement (append to `lib/fetch.sh`)**

```bash
fetch_url_key() { # url -> stable cache key
  local url="$1" base; base="$(basename "${url%%\?*}")"
  printf 'url_%s_%s' "$(printf '%s' "$url" | sha256sum | cut -c1-16)" "$base"
}

fetch_url() { # url sha256|-  -> prints cached path; downloads if absent
  local url="$1" sha="$2"; mkdir -p "$FETCH_CACHE"
  local path="$FETCH_CACHE/$(fetch_url_key "$url")"
  if [ ! -f "$path" ]; then
    curl -fsL -o "$path" "$url" || { rm -f "$path"; echo "fetch: download failed: $url" >&2; return 1; }
  fi
  if [ "$sha" != "-" ]; then
    local got; got="$(sha256sum "$path" | cut -d' ' -f1)"
    [ "$got" = "$sha" ] || { rm -f "$path"; echo "fetch: sha256 mismatch for $(fetch_url_key "$url") (got $got want $sha)" >&2; return 1; }
  else
    echo "fetch: $(fetch_url_key "$url") sha256=$(sha256sum "$path" | cut -d' ' -f1) (pin this in sources.toml)" >&2
  fi
  printf '%s' "$path"
}
```

- [ ] **Step 4: Run → passes** (`pass=4 fail=0`). `bash tests/test_fetch.sh`.

- [ ] **Step 5: Allow `url` in manifest validation**

In `lib/manifest.sh` `manifest_validate`, change the bundle-type check to include `url`:
```bash
  if printf '%s' "$json" | jq -e '.bundle[] | select((.type // "") as $t | ($t|IN("github","gitlab","local","url"))|not)' >/dev/null; then
    echo "manifest: bundle.type must be github|gitlab|local|url" >&2; return 1; fi
```
Add a fixture `tests/fixtures/url-ok.toml`:
```toml
package = "com.strava"
app_version = "460.9"
engine = "revanced"
apk = "apks/com.strava.apks"

[[bundle]]
type = "url"
url = "https://api.revanced.app/v5/patches.rvp"
```
Append assertion to `tests/test_manifest.sh` before `t_summary`:
```bash
assert_eq "$(manifest_validate "$FX/url-ok.toml" >/dev/null 2>&1; echo $?)" "0" "url bundle valid"
```

- [ ] **Step 6: Run → passes** (`pass=14 fail=0`). `bash tests/test_manifest.sh`.

- [ ] **Step 7: Add the `url)` case to `resolve.sh` `resolve_bundles`**

Inside the `case "$type" in` block, add before the `*)` arm:
```bash
      url)
        local u sha
        u="$(printf '%s' "$json" | jq -r ".bundle[$i].url")"
        sha="$(printf '%s' "$json" | jq -r ".bundle[$i].sha256 // \"-\"")"
        fetch_url "$u" "$sha" >> "$out" || return 1; echo >> "$out" ;;
```

- [ ] **Step 8: Full suite + commit**

```bash
bash tests/run.sh 2>/dev/null || for t in tests/test_*.sh; do bash "$t"; done
git add lib/fetch.sh lib/manifest.sh lib/resolve.sh tests/test_fetch.sh tests/test_manifest.sh tests/fixtures/url-ok.toml
git commit -m "feat(fetch): url bundle type for prebuilt .rvp/.mpp from a plain URL"
```

---

## Task 7c: revanced manifest apps reuse the legacy sign/repack pipeline

Rationale: the manifest branch self-runs `java` and self-signs a single APK — correct for morphe (one merged universal APK). But revanced apps install as multi-split `.apks` bundles needing the existing extract→patch→sign-all-splits→repack pipeline. Rather than duplicate that, revanced manifest apps set the resolved inputs and **fall through** to the legacy pipeline (which already honors pre-set `REVANCED_CLI`/`APK_FILE`/`PATCHES_JAR`).

**Files:**
- Modify: `patch-apks.sh` (split the manifest branch by engine)
- Test: manual `--resolve-only` for both a morphe and a revanced manifest (Task 8)

**Interfaces:** none new.

- [ ] **Step 1: Restructure the manifest branch** so only morphe self-completes; revanced sets vars and falls through.

Replace the body after `mapfile -t CLI_ARGS ...` (the `if RESOLVE_ONLY ... java ... exit 0` block) with an engine split. The new branch shape:

```bash
if [ -n "$MANIFEST" ]; then
    manifest_validate "$MANIFEST" || exit 1
    JSON="$(manifest_to_json "$MANIFEST")"
    ENGINE="$(printf '%s' "$JSON" | jq -r '.engine')"
    APKREL="$(printf '%s' "$JSON" | jq -r '.apk')"
    APP_DIR="apps/$APP"; APK_IN="$APP_DIR/$APKREL"
    [ -f "$APK_IN" ] || err "manifest apk not found: $APK_IN"
    CLI_JAR="$(engine_cli_path "$ENGINE")" || exit 1
    BUNDLES_FILE="$(mktemp)"; trap 'rm -f "$BUNDLES_FILE"' EXIT
    resolve_bundles "$JSON" "$APP_DIR" "$BUNDLES_FILE" || exit 1

    if [ "$ENGINE" = morphe ]; then
        OUT_APK="build/${APP}-patched.apk"; mkdir -p build
        mapfile -t CLI_ARGS < <(engine_morphe_args "$JSON" "$CLI_JAR" "$APK_IN" "$OUT_APK" "$BUNDLES_FILE")
        if [ "${RESOLVE_ONLY:-false}" = true ]; then
            echo "app:     $APP"; echo "engine:  morphe"; echo "cli:     $CLI_JAR"; echo "input:   $APK_IN"
            echo "bundles:"; sed 's/^/  /' "$BUNDLES_FILE"
            echo "command: java ${CLI_ARGS[*]}"; exit 0
        fi
        java "${CLI_ARGS[@]}" || err "patching failed"
        echo "Patched → $OUT_APK"
        echo "Install: \"\$ADB\" install \"$(wslpath -w "$PWD/$OUT_APK" 2>/dev/null || echo "$PWD/$OUT_APK")\""
        exit 0
    fi

    # revanced: feed the legacy pipeline (it already extracts .apks, patches base,
    # signs every split with one key, and repacks). Legacy honors these pre-set vars.
    REVANCED_CLI="$CLI_JAR"
    APK_FILE="$APK_IN"
    PATCHES_JAR="$(head -1 "$BUNDLES_FILE")"     # legacy applies one bundle; revanced manifests pin one
    NO_UI=true                                    # apply all default-enabled patches (manifest reproducible)
    if [ "${RESOLVE_ONLY:-false}" = true ]; then
        echo "app:     $APP"; echo "engine:  revanced (→ legacy pipeline)"; echo "cli:     $REVANCED_CLI"
        echo "input:   $APK_FILE"; echo "bundles:"; sed 's/^/  /' "$BUNDLES_FILE"
        echo "(revanced manifest apps run the legacy extract/patch/sign/repack path)"; exit 0
    fi
    # fall through — do NOT exit; legacy pipeline below uses REVANCED_CLI/APK_FILE/PATCHES_JAR/NO_UI
fi
```

Note: keep the `_LIB` sourcing, the `--resolve-only` flag, and the gate (`MANIFEST` computed from `--app` + no override + `sources.toml` exists) exactly as Task 7 left them. Only the inside-the-branch engine split changes. Remove the old unconditional `rm -f "$BUNDLES_FILE"` lines (the `trap` now handles cleanup on every exit path — fixes the Task-7 review's Minor temp-leak finding).

- [ ] **Step 2: Verify legacy honors the pre-set vars**

Read `patch-apks.sh` below the branch: confirm `REVANCED_CLI` is only auto-picked `if [[ -z "$REVANCED_CLI" ]]`, `PATCHES_JAR` only looked up `if [[ -z "$PATCHES_JAR" ]]`, and `APK_FILE` is used when set. If any unconditionally overwrites a pre-set value, adjust to respect it. Report the exact guard lines.

- [ ] **Step 3: Syntax + regression**

```bash
bash -n patch-apks.sh && echo OK
for t in tests/test_*.sh; do bash "$t"; done   # all fail=0
./patch-apks.sh --help >/dev/null && echo "help OK"
```

- [ ] **Step 4: Commit**

```bash
git add patch-apks.sh
git commit -m "feat(driver): revanced manifest apps reuse legacy sign/repack; trap-clean temp"
```

---

## Task 8: Migration — write `sources.toml` for all apps

**Files:**
- Create: `apps/{twitter,strava,hidratespark,meetup,tinder,metoffice,foldersync}/sources.toml`
- Modify: `engines.toml` (set real `revanced.version`)

**Interfaces:** none new; consumes everything above.

- [ ] **Step 1: Pin the revanced CLI version**

Find the revanced-cli jar currently used (repo root) or latest release; set `engines.toml` `[revanced] version`. Verify fetch works:
```bash
# confirm the revanced-cli release asset name/host; adjust engine_cli_path revanced) line if GitLab-hosted
gh api repos/ReVanced/revanced-cli/releases/latest --jq '.tag_name,(.assets[].name)' 2>&1 | head
```
If GitHub 404s (DMCA), switch to the GitLab ReVanced project in `engine_cli_path` and re-verify. Set the resolved version in `engines.toml`.

- [ ] **Step 2: Write `apps/twitter/sources.toml` (the reference — morphe)**

```toml
package     = "com.twitter.android"
app_version = "12.2.0-release.0"
engine      = "morphe"
apk         = "apks/x-12.2.0.apkm"

[[bundle]]
type = "github"
repo = "crimera/piko"
version = "3.7.0"

[[bundle]]
type = "gitlab"
repo = "inotia00/x-shim"
version = "1.7.0"
```

- [ ] **Step 3: Write local-engine manifests (revanced, `type=local`)**

For each of `hidratespark, meetup, tinder, metoffice, foldersync`, create `apps/<app>/sources.toml` (read package/version/apk from each `apps/<app>/README.md`). Example `apps/meetup/sources.toml`:
```toml
package     = "com.meetup"
app_version = "2026.04.10.2881"
engine      = "revanced"
apk         = "apks/base.apk"

[[bundle]]
type = "local"
project = "meetup"
```
Repeat with the correct `package`/`app_version`/`apk` per app. **Decision:** if an app is a `.apks` split bundle that needs the legacy per-run keystore split-signing, omit its manifest and leave it on the legacy path (document in the app's README). Single-`base.apk` local apps are fine on the manifest path.

- [ ] **Step 4: Write `apps/strava/sources.toml` (revanced, remote `.rvp`)**

Strava consumes an upstream `patches-<ver>.rvp`. Pin it:
```toml
package     = "com.strava"
app_version = "460.9"
engine      = "revanced"
apk         = "apks/base.apk"

[[bundle]]
type    = "gitlab"           # or github, whichever hosts the upstream Strava .rvp
repo    = "ReVanced/revanced-patches"
version = "<pinned-tag>"
asset   = "patches-<ver>.rvp"
```
Verify the exact host/repo/asset for the Strava `.rvp` currently used; adjust.

- [ ] **Step 5: Verify each manifest resolves**

```bash
for a in twitter strava hidratespark meetup tinder metoffice foldersync; do
  [ -f "apps/$a/sources.toml" ] && { echo "== $a =="; ./patch-apks.sh --app "$a" --resolve-only || echo "  (resolve failed)"; }
done
```
Expected: each prints a coherent plan (engine, CLI, bundles, command). Fix any manifest whose resolve fails.

- [ ] **Step 6: Run the full unit suite**

```bash
for t in tests/test_*.sh; do echo "== $t =="; bash "$t" || exit 1; done
```
Expected: every file ends `fail=0`.

- [ ] **Step 7: Commit**

```bash
git add apps/*/sources.toml engines.toml
git commit -m "feat(migration): sources.toml for all apps; pin engine versions"
```

---

## Task 9: End-to-end smoke + docs

**Files:**
- Modify: `CLAUDE.md` (document the manifest flow + `--resolve-only`)
- Create: `tests/run.sh` (run all unit tests)

**Interfaces:** none new.

- [ ] **Step 1: Add the test runner**

Create `tests/run.sh`:
```bash
#!/usr/bin/env bash
set -e
cd "$(dirname "$0")"
fail=0
for t in test_*.sh; do echo "== $t =="; bash "$t" || fail=1; done
exit $fail
```

- [ ] **Step 2: End-to-end — twitter reproduces the working X build**

Run:
```bash
./patch-apks.sh --app twitter
```
Expected: produces `build/twitter-patched.apk`; prints an `adb install` line. (Optional device check: uninstall stock, install, launch — matches the verified 12.2.0 result. Only if a device is attached.)

- [ ] **Step 3: End-to-end — a local app via the manifest path**

Run:
```bash
./patch-apks.sh --app hidratespark
```
Expected: builds `patches/hidratespark` jar, applies via revanced-cli, outputs `build/hidratespark-patched.apk`. Compare patch set against a legacy run (`--apk apps/hidratespark/apks/base.apk --patches patches/hidratespark/build/libs/*.jar`) — same patches applied.

- [ ] **Step 4: Update `CLAUDE.md`**

Add a "Manifest applier" subsection under Commands/Architecture documenting: `sources.toml` schema, `engines.toml`, `--resolve-only`, the one-engine-per-app rule, `type=local`⇒revanced, and that bundles/CLIs live in gitignored `bin/`+`.cache/`. Note the twitter manifest is the reference morphe example.

- [ ] **Step 5: Run the full suite once more**

```bash
bash tests/run.sh
```
Expected: all `fail=0`.

- [ ] **Step 6: Commit**

```bash
git add tests/run.sh CLAUDE.md
git commit -m "docs+test: manifest flow docs, end-to-end smoke, test runner"
```

---

## Self-Review

**Spec coverage:**
- Manifest schema (engine/apk/[[bundle]]/[patches]) → Tasks 1,2,5,8. ✓
- Auto-fetch pinned+cached bundles → Task 3. ✓
- Engine CLI auto-management (`engines.toml`+`bin/`) → Task 4. ✓
- Unified scope (every app incl. local) → Tasks 6,8. ✓
- Patch selection in manifest → Task 5. ✓
- Driver refactor + `--resolve-only` → Task 7. ✓
- One-engine-per-app + local⇒revanced constraints → Task 2 (validate). ✓
- Migration of 7 apps → Task 8. ✓
- Testing (`--resolve-only`, e2e twitter/local, error cases) → Tasks 8,9 + error fixtures Task 2. ✓
- Non-goals respected (no GUI/manager/cross-engine merge). ✓

**Placeholder scan:** `engines.toml` `revanced.version="TBD-at-migration"` and strava `version="<pinned-tag>"` are resolved in Task 8 with explicit verification commands — intentional, not silent placeholders. No "add error handling"/"write tests"-style gaps; all code shown.

**Type consistency:** `manifest_to_json`/`manifest_get`/`manifest_validate` (Tasks 1–2) reused verbatim downstream. `fetch_asset`/`fetch_cache_key`/`fetch_gitlab_project_id`/`engine_cli_path` (Tasks 3–4) match call sites in Tasks 6–7. `engine_morphe_args`/`engine_revanced_args`/`_engine_selection_lines`/`resolve_bundles`/`resolve_local_jar` names consistent across Tasks 5–7. Driver calls `engine_"${ENGINE}"_args` — matches both function names. ✓

**Known risk to verify during execution:** exact revanced-cli release host/asset name (GitHub vs GitLab post-DMCA) — Task 8 Step 1 verifies before relying on it.
