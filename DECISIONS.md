# DECISIONS.md — Research findings for opencode-godmode installer

Investigated 2026-08-08. Primary sources only (GitHub repos + official docs), fetched directly
(raw.githubusercontent.com + WebFetch), not from memory. Every claim below is sourced; anything
not confirmed is marked **UNCONFIRMED** instead of guessed.

**Independent cross-check (main session, same day):** re-fetched the gentle-ai install script,
the `opencode.ai/install` redirect target, and the rtk README directly — all core claims
(`Gentleman-Programming/gentle-ai`, the `anomalyco/opencode` rename, rtk's install URL/flags/
crates.io collision) confirmed. One correction applied: `OPENCODE_INSTALL_DIR` is not actually
read by the live install script — see (j). Also confirmed for real by installing OpenCode
natively in a fresh Ubuntu 26.04 WSL test environment: binary works at `~/.opencode/bin/opencode`.

## CRITICAL — read this before anything else

All three projects exist publicly, but **one name in the original brief is stale**:

- **gentle-ai** exists exactly as assumed: `github.com/Gentleman-Programming/gentle-ai`.
- **rtk** exists exactly as assumed: `github.com/rtk-ai/rtk`.
- **OpenCode's GitHub org changed.** It is **no longer `sst/opencode`**. SST rebranded to
  "Anomaly" in 2026 and the repo now lives at **`github.com/anomalyco/opencode`**
  ("The open source coding agent"). `sst/opencode` references are stale — GitHub may still
  redirect old URLs, but the installer, error messages, and any "install manually here" links
  shown to the user should point at `anomalyco/opencode` and at `https://opencode.ai/install`
  (which itself pulls binaries from `github.com/anomalyco/opencode/releases`), not `sst/opencode`.
  Source: `github.com/anomalyco/opencode`, and the install script served at
  `https://opencode.ai/install` (fetched directly — contains
  `url="https://github.com/anomalyco/opencode/releases/latest/download/$filename"`).

Also load-bearing for the plan: **`sdd-implement` does not exist.** The real phase name is
**`sdd-apply`**. See (b).

---

## (a) Non-interactive install / agent selection in gentle-ai

**Answer: Yes, fully non-interactive via CLI flags. No TUI is required.** The TUI (`gentle-ai`
with no args) is the default/interactive path, but `gentle-ai install` accepts flags that skip
it entirely:

```bash
gentle-ai install \
  --agent opencode \
  --preset full-gentleman \
  --component engram,sdd,skills,context7,persona,permissions \
  --persona gentleman \
  --sdd-mode multi \
  --scope=global \
  --dry-run      # drop this flag to actually apply
```

Flag reference (from `docs/usage.md`):

| Flag | Values |
|---|---|
| `--agent`, `--agents` | comma-separated agent IDs, e.g. `opencode` |
| `--component`, `--components` | comma-separated: `engram,sdd,skills,context7,persona,permissions,gga,theme` |
| `--skill`, `--skills` | comma-separated skill IDs |
| `--persona` | `gentleman` \| `neutral` \| `custom` |
| `--preset` | `full-gentleman` \| `ecosystem-only` \| `minimal` \| `custom` |
| `--sdd-mode` | `single` \| `multi` |
| `--scope` | `global` (default) \| `workspace` — also settable via env var `GENTLE_AI_INSTALL_SCOPE` (explicitly documented as "for CI/non-interactive use") |
| `--dry-run` | preview only, no writes |

Self-update prompts (separate from `install`) respect `GENTLE_AI_YES=1` (auto-accept,
inherited by subprocesses — scope it to one invocation) and `GENTLE_AI_NO_SELF_UPDATE=1`
(skip entirely). Non-TTY contexts (CI, piped) already auto-decline self-update prompts without
hanging.

`gentle-ai install` requires Node.js 18+ and npm on **every** platform (checked regardless of
which agents/components you pick) and warns with a distro-specific hint if missing — on
Debian/Ubuntu that hint is "NodeSource LTS setup + `apt-get install -y nodejs`" (npm bundled).
It does **not** install Node for you, and does **not** install agent runtimes (OpenCode) either
— if the selected agent isn't detected on PATH, it refuses and prints the exact command to run.

Sources:
- https://github.com/Gentleman-Programming/gentle-ai/blob/main/docs/usage.md
- https://github.com/Gentleman-Programming/gentle-ai/blob/main/docs/quickstart.md
- https://github.com/Gentleman-Programming/gentle-ai/blob/main/README.md

**Design decision for install.sh:** Always call `gentle-ai install` with explicit `--agent
opencode --preset ... --scope=global` (or `workspace`, matching wherever the rest of the stack
targets) rather than invoking bare `gentle-ai`. This guarantees no TUI ever launches during an
unattended `install.sh` run. Check `node --version` / `npm --version` yourself *before* calling
`gentle-ai install` and run the NodeSource + `apt-get install -y nodejs` sequence proactively on
Debian/Ubuntu if missing, instead of relying on gentle-ai's warning (which does not install
anything).

---

## (b) Exact SDD phase names — `sdd-implement` does NOT exist

**Answer:** gentle-ai's SDD workflow has exactly **10 phases**, all literally prefixed `sdd-`:

```
sdd-init
sdd-explore
sdd-propose
sdd-spec
sdd-design
sdd-tasks
sdd-apply       <- this is "implement", NOT "sdd-implement"
sdd-verify
sdd-archive
sdd-onboard
```

(Confirmed verbatim in `docs/components.md`'s skills table AND in `docs/opencode-profiles.md`'s
"Key Names To Remember" table, which explicitly gives `sdd-{phase}` example `sdd-apply` and shows
the working CLI example `gentle-ai sync --profile-phase cheap:sdd-apply:anthropic/claude-sonnet-4-20250514`.)

`sdd-implement` never appears as a phase ID anywhere in the repo's docs. **"implement" is prose
shorthand some docs pages use informally for the `sdd-apply` phase** (e.g. `docs/intended-usage.md`
loosely says "phases (explore, propose, spec, design, implement, verify)" in a sentence aimed at
end users who don't need to memorize IDs) — but the machine-facing phase ID used by `--profile-phase`,
by the generated `opencode.json` agent keys (`sdd-{phase}-{name}`), and by the skill registry is
always `sdd-apply`. There is no separate "does implement inherit the base model" question — `sdd-apply`
is a first-class phase exactly like the other nine, and gets its own model assignment slot in
multi-mode; it does not implicitly inherit anything more than any other unassigned phase would
(unassigned phases fall back to the profile's base/default model).

`gentle-ai sync --profile-phase` syntax: `name:phase:provider/model`, e.g.:

```bash
gentle-ai sync \
  --profile cheap:anthropic/claude-haiku-3.5-20241022 \
  --profile-phase cheap:sdd-apply:anthropic/claude-sonnet-4-20250514
```

Sources:
- https://github.com/Gentleman-Programming/gentle-ai/blob/main/docs/components.md
- https://github.com/Gentleman-Programming/gentle-ai/blob/main/docs/opencode-profiles.md
- https://github.com/Gentleman-Programming/gentle-ai/blob/main/docs/intended-usage.md

**Design decision:** Anywhere the plan/spec says `sdd-implement`, rename to `sdd-apply`. Any
`--profile-phase` calls in install.sh/verify.sh must use `sdd-apply` literally, e.g. for a
"stronger model for implementation" default: `--profile-phase <name>:sdd-apply:<provider/model>`.

---

## (c) Where gentle-ai stores config for OpenCode, and gentle-ai's own state

**Two different things, don't conflate them:**

1. **gentle-ai's own install-selection state** (what agents/components you told it to manage):
   `~/.gentle-ai/state.json` — JSON. Holds `installed_agents` list and `model_assignments`.
   `gentle-ai sync` (no `--agent` flag) reads this file to know what to update; running
   `install --agent X` merges X into the existing `installed_agents` list rather than overwriting.
   `gentle-ai doctor` validates this file parses correctly ("state.json validity" check).

2. **The actual OpenCode agent config gentle-ai generates**:
   `~/.config/opencode/opencode.json` — JSON. This is OpenCode's own native config file;
   gentle-ai writes into it a "full multi-agent overlay": the base orchestrator key
   `gentle-orchestrator`, plus (in multi-mode with named profiles) `sdd-orchestrator-{name}`
   and 10 suffixed phase sub-agents per profile, `sdd-{phase}-{name}` (e.g.
   `sdd-apply-cheap`). Model-variant/reasoning-effort cache used by the profile picker lives
   separately at `~/.gentle-ai/cache/model-variants.json`. The bundled OpenCode plugin that
   gentle-ai installs lives under `~/.config/opencode/plugins/`.
   If you're using a **community external profile manager** instead of gentle-ai's generated
   overlay, that tool stores profile files at `~/.config/opencode/profiles/*.json` — gentle-ai
   auto-detects those on `sync` and switches to an `external-single-active` compatibility
   strategy (force with `--sdd-profile-strategy external-single-active|generated-multi`).

3. **Project-level SDD context** (optional, written by `/sdd-init` inside the agent, not by the
   `gentle-ai` binary): `openspec/config.yaml` — YAML, in the project root. **Caveat, stated
   explicitly by gentle-ai's own docs:** this file's shape is "prompt-driven," not enforced by
   any Go-side parser/validator — it's a convention the SDD skill prompts follow, not a locked
   schema. Expected top-level keys per the docs' synthesized example: `schema` (literal
   `spec-driven`), `context` (multiline string), `strict_tdd` (bool), `rules` (map keyed by
   `proposal|specs|design|tasks|apply|verify|archive`), `testing` (object with `strict_tdd`,
   `detected`, `runner.command`, `runner.framework`).

4. **Project-level skill registry** (written by `gentle-ai skill-registry refresh`, not by
   `/sdd-init`): `.atl/skill-registry.md` (human-readable) and
   `.atl/.skill-registry.cache.json` (machine cache: schema version + per-`SKILL.md` path/mtime/size)
   — both in the project root. This one **is** reliably written by a real CLI command with a
   documented, stable file path — use this one for programmatic checks, not `openspec/config.yaml`.

Sources:
- https://github.com/Gentleman-Programming/gentle-ai/blob/main/docs/usage.md
- https://github.com/Gentleman-Programming/gentle-ai/blob/main/docs/opencode-profiles.md
- https://github.com/Gentleman-Programming/gentle-ai/blob/main/docs/openspec-config.md
- https://github.com/Gentleman-Programming/gentle-ai/blob/main/docs/platforms.md (Windows path
  table confirms the Linux paths above are `~/.config/...`, not OS-specific quirks)

**Design decision for verify.sh:** Validate with `jq`:
- `jq -e '.installed_agents | index("opencode")' ~/.gentle-ai/state.json` — confirms gentle-ai
  thinks OpenCode is managed.
- `jq -e '."gentle-orchestrator"' ~/.config/opencode/opencode.json` (exact key path depends on
  gentle-ai's actual schema — dry-run install first and inspect the real output before hardcoding
  a `jq` path in production; the docs describe the *keys that exist*, not the full nesting of
  `opencode.json`).
- Do **not** hard-require `openspec/config.yaml` to exist as a pass/fail gate — it's explicitly
  documented as best-effort/prompt-driven and may not be created if the project uses
  Engram-only (non-openspec) persistence. Treat its presence as informational, not authoritative.

---

## (d) gentle-ai version command and uninstall

**Version:**
```bash
gentle-ai version
gentle-ai --version
gentle-ai -v
```
All three work (documented together in `docs/usage.md`).

**Uninstall** (official, not just "delete the binary"):
```bash
# Remove all managed components for specific agents
gentle-ai uninstall --agent claude-code --agent opencode

# Remove specific components only, for specific agents
gentle-ai uninstall --agent claude-code --component sdd,persona,context7

# Nuke everything gentle-ai manages, across all supported agents
gentle-ai uninstall --all

# Skip the confirmation prompt (needed for a non-interactive uninstall.sh)
gentle-ai uninstall --agent opencode --component skills --yes
```
If `--component` is omitted, it removes *all* managed uninstallable components for the selected
agents. This only removes gentle-ai-managed fragments (prompt sections, MCP entries, skill/config
fragments) from the agent's config — it does **not** remove the agent itself (OpenCode) or the
`gentle-ai` binary. Before any change, gentle-ai writes a backup snapshot of affected files first
(compressed, deduplicated, auto-pruned to the 5 most recent per the README).

To remove the `gentle-ai` binary itself: no dedicated command exists — since it's typically
installed via the curl script (which downloads a binary, likely to a user-local bin dir) or
`go install` or `brew install gentle-ai`, removal is the inverse of the install method
(`brew uninstall gentle-ai`, or `rm` the binary from wherever the install script placed it — the
install script content wasn't fully inspected for its exact target directory, treat as
**UNCONFIRMED**: re-check `scripts/install.sh` for `--dir`/default install path before hardcoding
a path in uninstall.sh).

Sources:
- https://github.com/Gentleman-Programming/gentle-ai/blob/main/docs/usage.md
- https://github.com/Gentleman-Programming/gentle-ai/blob/main/README.md

**Design decision:** uninstall.sh should call `gentle-ai uninstall --agent opencode --all --yes`
(or `--component` scoped to exactly what install.sh installed) before removing the `gentle-ai`
binary path itself, and should not assume `gentle-ai uninstall` removes the binary.

---

## (e) Confirming SDD project registration programmatically (no human prompt)

**Answer: partial.** There is no single "is this project registered" gentle-ai command with a
clean exit code. What's actually confirmable without asking a human:

1. **Skill registry refresh — reliably checkable.** `gentle-ai skill-registry refresh` (or
   `--force`, or `--cwd /path --quiet`) writes two files that are documented as stable outputs:
   `.atl/skill-registry.md` and `.atl/.skill-registry.cache.json` in the project root. Check
   both exist and that the cache JSON parses (`jq -e . .atl/.skill-registry.cache.json`) and its
   fingerprint/schema-version field is non-null.

2. **`/sdd-init` — not reliably checkable via a stable file contract.** `/sdd-init` is a
   slash-command run *inside* the agent conversation, not a `gentle-ai` CLI subcommand — there's
   no shell exit code to check. Its most likely artifact, `openspec/config.yaml`, is explicitly
   documented as prompt-driven convention, not a guaranteed/enforced output (see (c)). It is only
   written "in `openspec` or `hybrid` persistence modes" — in Engram-only mode it may never be
   created at all, so its absence is not proof `/sdd-init` failed.

3. There is a `/gentle-ai:status` (or similarly named) **slash command that runs inside the
   agent**, referenced informally in search results as showing "package, SDD assets, OpenSpec,
   and global model config" status — but this was **not found as primary-source-verified text**
   in the repo's own docs during this research (it surfaced only via a secondary search snippet,
   not a fetched doc page). Treat its existence/exact name as **UNCONFIRMED** — do not build
   install.sh logic around it without verifying directly against the repo's `cmd/gentle-ai`
   source or a fetched doc page that names it explicitly.

4. `gentle-ai doctor` is a real, confirmed, read-only command, but it checks *gentle-ai's own*
   ecosystem health (tool binaries on PATH, `~/.gentle-ai/state.json` validity, Engram MCP
   reachability, disk space) — **not** whether a specific project ran `/sdd-init`.

Sources:
- https://github.com/Gentleman-Programming/gentle-ai/blob/main/docs/usage.md
- https://github.com/Gentleman-Programming/gentle-ai/blob/main/docs/openspec-config.md
- https://github.com/Gentleman-Programming/gentle-ai/blob/main/README.md

**Design decision:** In verify.sh, treat `.atl/skill-registry.md` +
`.atl/.skill-registry.cache.json` existing (and the cache JSON being valid JSON with a
recognizable schema-version key) as the authoritative, scriptable proof that project
registration happened — this is the one gentle-ai actually documents as a stable file contract.
Log `openspec/config.yaml` presence as informational only ("SDD context file found/not found —
not required"), never as a hard failure. Do not build automation around an unverified
`/gentle-ai:status` slash command.

---

## (f) Lightweight command to test/list configured models

**gentle-ai itself has no standalone "ping the provider" CLI command** — model
testing/assignment happens through the TUI's "Configure Models" screen (per `docs/usage.md`).

**OpenCode does**, and it's the practical answer here:
```bash
opencode models            # list all available models in provider/model format
opencode models --refresh  # force-refresh the cached model list (hits the provider)
```
`opencode models --refresh` is also the exact mechanism gentle-ai's own docs point to for
populating the reasoning-effort cache (`~/.gentle-ai/cache/model-variants.json`) that the profile
picker reads — gentle-ai's own multi-mode setup guide says: "connect your AI providers first,
then run `opencode models --refresh`" as the documented prerequisite step before configuring
per-phase models. So this is not just incidentally useful, it's the same command gentle-ai's
own workflow depends on.

Sources:
- https://github.com/Gentleman-Programming/gentle-ai/blob/main/docs/agents.md
- https://github.com/Gentleman-Programming/gentle-ai/blob/main/docs/opencode-profiles.md
- https://opencode.ai/docs/cli/

**Design decision:** verify.sh's "does the configured provider actually respond" check should
shell out to `opencode models --refresh` (or `opencode models <provider>` for a specific
provider) and check for a non-empty model list / exit code 0, rather than inventing a gentle-ai
check that doesn't exist.

---

## (g) Reading/writing TOML with python3 stdlib only (no pip)

**Ubuntu/Debian Python versions actually relevant to an apt-targeted installer:**
- Ubuntu 24.04 LTS (still the dominant current LTS): **Python 3.12**.
- Debian 13 "trixie" (current stable as of this research): **Python 3.13**
  (`packages.debian.org/trixie/python3`).
- Ubuntu 26.04 LTS (released since this task's current date, 2026-08-08, is after its April 2026
  ship date): reported as shipping **Python 3.14**.
- All of the above are ≥3.11, so **`tomllib` (read-only) is available out of the box on every
  realistic Debian/Ubuntu apt target** — no `pip install` needed for parsing.

**The gap is writing.** `tomllib` is read-only by design (CPython core devs deliberately excluded
a writer from stdlib); there is still no `tomlw`/`tomllib`-write equivalent in any released
CPython version as of this research. Third-party writers (`tomli-w`, `tomlkit`) require `pip
install`, which the installer should avoid per its own constraints.

**Simplest dependency-free pattern for a *known, controlled* file like `templates/rtk-config.toml`:**
Do NOT attempt a general-purpose "parse arbitrary TOML → mutate → reserialize" round-trip in
Python — that's exactly the hard part stdlib doesn't solve. Instead:

1. Ship `templates/rtk-config.toml` as a static, complete template (full schema, see (i) below)
   that install.sh drops in place with `cp`/heredoc if no config exists yet.
2. If a config **already exists** (upgrade/re-run case), do a **non-destructive merge using
   `tomllib` for reads only**: parse the existing file with `tomllib.load()` to get current
   values as a dict, decide which specific keys need to change, then **write only via targeted,
   idempotent text edits** (regex/line-based find-or-append per `[section]` + `key = value`
   pair) against the original file text — never regenerate the whole file from the parsed dict.
   This preserves comments, key order, and any manual edits, and sidesteps needing a TOML
   serializer entirely. This is exactly the pattern `rtk`'s own filter-trust system implies is
   safe (SHA-256-gated trust of hand-edited files) — treat user TOML as text-preserving, not
   as a round-trippable object.
3. Simpler still: **prefer `rtk config --create`** (see (i)) to generate the canonical default
   file via `rtk` itself, then only patch specific keys with the text-edit approach above if the
   installer needs non-default values — avoids hand-rolling TOML *generation* altogether for the
   rtk config specifically.

Sources:
- https://packages.debian.org/trixie/python3
- https://computingforgeeks.com/install-python-ubuntu-2604/ (Python 3.14 on Ubuntu 26.04 LTS)
- https://raw.githubusercontent.com/rtk-ai/rtk/master/docs/guide/getting-started/configuration.md
  (`rtk config --create`)

**Design decision:** Use `python3 -c "import tomllib; ..."` (or a small script) only for
**validation** in verify.sh (`tomllib.load(open(path,'rb'))` — raises on invalid TOML, exits
non-zero). For **writing/merging** `templates/rtk-config.toml` into `~/.config/rtk/config.toml`,
use `rtk config --create` as the base generator plus shell/`sed`-based idempotent key patching,
not a Python TOML writer.

---

## (h) Official gentle-ai curl install command

**Confirmed correct as originally assumed:**
```bash
curl -fsSL https://raw.githubusercontent.com/Gentleman-Programming/gentle-ai/main/scripts/install.sh | bash
```
This URL was fetched directly and returns a real bash script (`GITHUB_OWNER="Gentleman-Programming"`,
`GITHUB_REPO="gentle-ai"`, supports `--method brew|go|binary`, `--channel stable|beta|nightly`,
`--dir DIR`, `--insecure`).

Beta channel variant:
```bash
curl -fsSL https://raw.githubusercontent.com/Gentleman-Programming/gentle-ai/main/scripts/install.sh | bash -s -- --channel beta
```

Alternative install methods documented in the README, all valid on Debian/Ubuntu:
```bash
# Homebrew on Linux (requires one-time tap trust)
brew tap Gentleman-Programming/homebrew-tap
brew trust --formula gentleman-programming/tap/gentle-ai
brew install gentle-ai

# Go (any platform, Go 1.25.10+)
go install github.com/gentleman-programming/gentle-ai/v2/cmd/gentle-ai@latest
```
Note the `/v2` suffix is required for the v2.x line; a `v1.46.0` pin (last pre-RDD stable release)
uses the unsuffixed import path instead — mixing them makes `go install` refuse the tag.

Sources:
- https://raw.githubusercontent.com/Gentleman-Programming/gentle-ai/main/scripts/install.sh
  (fetched directly, header comment literally contains this curl command)
- https://github.com/Gentleman-Programming/gentle-ai/blob/main/README.md

**Design decision:** Use the curl command exactly as given (apt/Debian target = Linux, script
auto-detects and uses `apt`-appropriate logic internally per `docs/platforms.md`'s "Linux
(Ubuntu/Debian) → apt → Supported" row). No changes needed from the original plan for this URL.

---

## (i) Official rtk curl install, `rtk init` flags, version, `rtk gain` collision

**Install (confirmed correct as originally assumed, except note the redirect target used is
`refs/heads/master`, i.e. branch `master`, not `main`):**
```bash
curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/refs/heads/master/install.sh | sh
```
Installs to `~/.local/bin` — installer does not auto-add to PATH; README recommends:
```bash
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
```

**`rtk init` flags — your three assumptions, checked individually:**
- `rtk init -g --opencode` — **confirmed**, documented literally: "OpenCode plugin (instead of
  Claude Code)". Also written as `rtk init -g --agent opencode`-style pattern is NOT used here;
  it's specifically the `--opencode` boolean flag (unlike `--codex`, `--gemini` which are also
  bare boolean flags, vs. `--agent cursor`/`--agent windsurf`/etc. which take a value for agents
  without a dedicated boolean flag).
- `rtk init -g --uninstall` — **confirmed**, documented literally under "### Uninstall":
  `rtk init -g --uninstall     # Remove hook, RTK.md, settings.json entry`.
- `rtk init --show` — **confirmed**: "Verify installation".
- Additional flags found: `--hook-only` (hook only, no RTK.md), `--auto-patch` (non-interactive,
  for CI/CD — useful for install.sh), `--trust-filters` / `--no-trust-filters` (non-interactive
  filter-trust decisions).

**Version:**
```bash
rtk --version   # e.g. "rtk 0.28.2"
```

**`rtk gain` crates.io collision — confirmed real, not invented:**
> "Another project named 'rtk' (Rust Type Kit) exists on crates.io. If `rtk gain` fails, you have
> the wrong package. Use `cargo install --git` above instead."

This is a real, documented warning in the rtk README's "Verify Installation" section. Practical
implication: if a Debian/Ubuntu machine ever has `cargo install rtk` run against it (plain crates.io
name, not `rtk-ai/rtk`'s git install), it silently installs the wrong "Rust Type Kit" binary under
the same `rtk` command name, and `rtk gain`/`rtk init`/etc. will fail or behave unexpectedly. The
official recommended install methods (curl script, Homebrew, `cargo install --git
https://github.com/rtk-ai/rtk`, or prebuilt release binaries) all sidestep this because none of
them go through plain `cargo install rtk`.

**Config file:** `~/.config/rtk/config.toml` (Linux) — full schema captured in (i)'s sibling
section below for `templates/rtk-config.toml`. `rtk config` shows current config; `rtk config
--create` generates one with documented defaults.

Sources:
- https://raw.githubusercontent.com/rtk-ai/rtk/master/README.md (fetched directly)
- https://raw.githubusercontent.com/rtk-ai/rtk/master/docs/guide/getting-started/configuration.md
  (fetched directly)

**Design decision for install.sh:** Use `rtk init -g --opencode --auto-patch` for a fully
non-interactive OpenCode-targeted install (verify `--auto-patch` combines cleanly with
`--opencode` — both are documented as independent boolean flags, no documented conflict found).
For uninstall.sh: `rtk init -g --uninstall`. For verify.sh: `rtk init --show` plus `rtk
--version` as a sanity check that the *correct* `rtk` binary (not the crates.io name-collision
package) is on PATH — e.g. assert the version string matches `rtk-ai/rtk`'s expected format/range,
and/or assert `rtk gain` exits 0.

**`templates/rtk-config.toml` — full canonical schema to ship** (from the fetched configuration
doc, all keys/defaults verbatim):
```toml
[tracking]
enabled = true
history_days = 90
# database_path = "/custom/path/history.db"

[display]
colors = true
emoji = true
max_width = 120

[filters]
ignore_dirs = [".git", "node_modules", "target", "__pycache__", ".venv", "vendor"]
ignore_files = ["*.lock", "*.min.js", "*.min.css"]

[tee]
enabled = true
mode = "failures"
max_files = 20
# directory = "/custom/tee/path"

[telemetry]
enabled = true

[hooks]
exclude_commands = []
```

---

## (j) Official non-apt install for OpenCode CLI on Linux

**Confirmed, and this IS the real "opencode" agent CLI (opencode.ai), separate from every other
similarly-named project:**
```bash
curl -fsSL https://opencode.ai/install | bash
```
Fetched this URL directly — it is a real bash installer (`APP=opencode`), auto-detects
`linux-x64`/`linux-arm64` (plus musl/baseline variants), downloads from GitHub releases, and
installs to **`$HOME/.opencode/bin`** (not `~/.local/bin`). It also supports:
```bash
curl -fsSL https://opencode.ai/install | bash -s -- --version 1.0.180   # pin a version
curl -fsSL https://opencode.ai/install | bash -s -- --no-modify-path    # don't touch .bashrc/.zshrc
```
**Correction after independent re-verification (main session, not the research subagent):**
`OPENCODE_INSTALL_DIR` is **NOT** read by the live script. Fetched
`https://raw.githubusercontent.com/anomalyco/opencode/refs/heads/dev/install` directly — it
hardcodes `INSTALL_DIR=$HOME/.opencode/bin` and only reads `VERSION` and `TMPDIR` from the
environment. Some third-party docs mirrors assert `OPENCODE_INSTALL_DIR` works; they are wrong
(or describe a different version). **Do not rely on it in install.sh.** The only supported way
to change install behavior is `--version <ver>` and `--no-modify-path` (both confirmed in the
live script). Also independently confirmed by installing for real in a clean Ubuntu 26.04 WSL
environment during this build: binary lands at `~/.opencode/bin/opencode`, and the script
appends a PATH export to `.bashrc` (interactive-shell-only, as usual for `.bashrc`).

The binary releases themselves are published at **`github.com/anomalyco/opencode/releases`** —
confirmed by the install script's own download URL construction
(`https://github.com/anomalyco/opencode/releases/latest/download/$filename`). This is the link
to show the user if `opencode` is not found on PATH: **`https://opencode.ai/install`** (primary,
user-facing) or `https://github.com/anomalyco/opencode` (source/releases, if they want to inspect
before piping to bash).

Sources:
- https://opencode.ai/install (fetched directly)
- https://github.com/anomalyco/opencode

**Design decision:** In install.sh/verify.sh, when `opencode` isn't on PATH, print exactly:
`curl -fsSL https://opencode.ai/install | bash` — and check `$HOME/.opencode/bin` specifically
(in addition to generic PATH lookup) since that's the confirmed real default install location,
not `~/.local/bin`. Never reference `sst/opencode` in user-facing text; use `opencode.ai` or
`anomalyco/opencode`.

---

## Addendum — corrections found by actually running install.sh (main session)

Found by real execution against a live gentle-ai 2.3.0 in the WSL Ubuntu test
environment, not by web research. Recorded here because they contradict both
PLAN.md and parts of the research above:

- **There is no `sdd-review` phase.** PLAN.md's step 6 originally said to sync
  `sdd-design` and `sdd-review` as the two "capable model" phases. `sdd-review`
  does not exist — `gentle-ai sync --profile-phase <name>:sdd-review:<model>`
  fails with `unknown phase "sdd-review"; valid phases are: [sdd-init
  sdd-explore sdd-propose sdd-spec sdd-design sdd-tasks sdd-apply sdd-verify
  sdd-archive sdd-onboard jd-judge-a jd-judge-b jd-fix-agent]` (exact error
  text from gentle-ai itself). The review/gate phase is **`sdd-verify`**.
  install.sh now syncs `sdd-verify` for `MODEL_REVIEW`. This is the same class
  of mistake as the `sdd-implement`→`sdd-apply` correction in (b) above — I
  should have cross-checked PLAN.md's phase names against my own findings in
  (b) instead of copying PLAN.md's text as-is; only caught it because I ran
  the real command instead of trusting the plan.
- **`opencode.json`'s orchestrator key is nested, not top-level.** The real
  shape is `{"agent": {"gentle-orchestrator": {...}, ...}, "default_agent":
  ..., "mcp": ..., "permission": ..., "share": ...}`. A `jq -e
  '."gentle-orchestrator"'` check against the file root always fails; it must
  be `jq -e '.agent."gentle-orchestrator"'`.
- **gentle-ai's and rtk's installers put binaries in `~/.local/bin` without
  ever touching shell rc files** (unlike OpenCode's installer, which does
  append to `.bashrc`). install.sh now unconditionally prepends
  `$HOME/.local/bin` to `PATH` near the top of the script, otherwise a second
  run from a shell that never sourced an updated `.bashrc` would think
  gentle-ai/rtk aren't installed and redundantly reinstall (breaks principle 4
  and 9). gentle-ai's own installer output claims the `engram` binary lives at
  `~/go/bin` — that was misleading in this environment; `which engram` showed
  `~/.local/bin/engram`, already covered by the same PATH fix.
- **Real `engram` CLI syntax is nothing like PLAN.md's `mem_save`/`mem_search`
  assumption** (those are the *MCP tool names* the agent calls, not the
  standalone CLI's flags — a distinction PLAN.md's "ciclo save/search/delete
  con la CLI de engram" glossed over and the research phase didn't catch
  either). Confirmed live:
  ```bash
  engram save <title> <msg> [--type TYPE] [--project PROJECT] [--scope SCOPE]
  engram search <query> [--type TYPE] [--project PROJECT] [--scope SCOPE] [--limit N]
  engram delete <obs_id> [--hard]     # obs_id parsed from `save`'s "Memory saved: #<id> ..." output
  engram version                      # exists and works (also `engram --version`)
  ```
  install.sh's smoke cycle now uses this real syntax, parsing the id with
  `grep -oE '#[0-9]+'` on `save`'s stdout.
- **`gentle-ai install --agent opencode --preset full-gentleman --sdd-mode
  multi --scope=global` genuinely works non-interactively** as (a) predicted —
  confirmed live: 64/64 file checks passed, real `opencode.json` written with
  `gentle-orchestrator` present, `sdd-apply.md` etc. all created. The
  `full-gentleman` preset also pulls in `gga` ("Gentleman Guardian Angel", a
  separate git-hook tool) as a side effect — not mentioned anywhere in
  PLAN.md, but it's exactly what depending on gentle-ai's bundled ecosystem
  (principle 2) means; left as-is rather than trying to exclude it via a
  narrower `--component` list, since the plan explicitly prioritizes riding
  gentle-ai's own preset curation over hand-picking components.

## Summary of naming corrections needed vs. the original plan

| Original assumption | Correct value |
|---|---|
| `sst/opencode` is the real OpenCode repo | **`anomalyco/opencode`** (SST rebranded to Anomaly in 2026; sst/opencode is stale) |
| SDD phase `sdd-implement` | **`sdd-apply`** (10 phases total: init, explore, propose, spec, design, tasks, apply, verify, archive, onboard) |
| gentle-ai install URL `.../main/scripts/install.sh` | Confirmed correct, no change |
| rtk install URL `.../refs/heads/master/install.sh` | Confirmed correct, no change |
| `rtk init -g --opencode`, `--uninstall`, `--show` | All three confirmed correct, no change |
| `rtk gain` crates.io collision | Confirmed real |
