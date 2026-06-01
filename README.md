# itential-integration-validator

End-to-end validator for OpenAPI specs intended for Itential integration models. Replaces the manual workflow of: import → create integration → grant role to group → open Studio → check the task palette.

One command tells you whether a spec produces a working set of callable tasks.

> ### ⚠ Scope of use
>
> **This tool is intended for a local dev stack that is dedicated to spec validation — not a stack where someone else is doing other work.**
>
> Validating a spec imports an integration model and a virtual instance into the platform, then deletes them. Bulk runs may do this hundreds of times in succession. Over time, the platform accumulates orphan roles in MongoDB and in-memory state in the worker process; recovery sometimes requires restarting the platform's container (see `platform-reset` below). Any of these operations will disrupt other testing happening on the same stack.
>
> Pointing this tool at a shared / preprod / production stack would create noise, may break others' in-progress work, and could leak credentials into Redis/MongoDB if the configured `admin@itential / admin` defaults don't match the target stack.

## Quick start
**Mac/Linux** system required, Windows is not compatible. 
```bash
# 1. Clone this repo (any method — HTTPS, SSH, gh CLI, etc.)
git clone https://github.com/nathaniel-itential/integration-model-validation.git
cd integration-model-validation

# 2. Run the installer
./install.sh

# 3. Edit config if your dev stack differs from defaults
$EDITOR ~/.claude/skills/validate-integration/config.json

# 4. Make sure your IAP dev stack is running
```

You'll get a PASS/PARTIAL/FAIL verdict with per-stage diagnostics in one screen for each spec you validate.

## What gets installed

| File | Purpose |
|---|---|
| `~/.local/bin/validate-integration` | The CLI — does all the work |
| `~/.claude/skills/validate-integration/SKILL.md` | Claude Code skill — invokes the CLI when you type `/validate-integration` |
| `~/.claude/skills/validate-integration/config.json` | Dev stack URL + credentials + default group + current asset branch |

## Usage

### Single spec (legacy default)

```bash
validate-integration <spec.json>                            # default group from config
validate-integration <spec.json> --group my_team_group      # override group
validate-integration <spec.json> --cleanup                  # delete instance + model after
validate-integration <spec.json> --json                     # machine-readable output
```

If the spec lives under `specs/`, it's automatically moved into the matching bucket (`validated/`, `partial/`, `failed/`) after the run. Re-running a spec that's already in `validated/` or `partial/` prompts for confirmation (pass `--force` to skip).

### Bulk validation from the assets repo

```bash
validate-integration fetch 5                # pull 5 unvalidated specs from github.com/itential/assets
validate-integration fetch --all            # pull every spec not already in any bucket
validate-integration fetch --branch main    # use a different branch

validate-integration bulk                   # validate everything in specs/unvalidated/
validate-integration bulk --rerun           # also re-run specs already in validated/
validate-integration bulk --no-rerun        # skip the rerun prompt entirely
validate-integration bulk --no-cleanup      # keep imported models around (default tears them down)

validate-integration status                 # bucket counts + sample listing

validate-integration clear --all             # delete every local spec (prompts first)
validate-integration clear --failed          # wipe a specific bucket
validate-integration clear --all --yes       # skip the confirmation
```

Bulk runs delete each imported model and instance after validating, since accumulating many models slows the platform down significantly. Pass `--no-cleanup` if you want to keep them around for inspection.

`clear` only removes the local spec files — integration models already imported into the IAP stack are not affected.

### When bulk crashes mid-run: `platform-reset`

```bash
validate-integration platform-reset
```

Over the course of a few back-to-back bulk runs, the platform's worker process accumulates in-memory state (leaked references, retained closures, socket pools) that it can't shed on its own. Eventually a bulk run will trip the validator's health check and abort with a "Platform health check failed" message.

`platform-reset` runs `docker restart <platform_container>` and polls until `POST /login` returns 200. **MongoDB, Redis, and all on-disk data are untouched** — only the platform's Node process is recycled, which is enough to clear the leak. Total time: ~30 seconds.

> **Same scope-of-use caveat applies.** This restarts the platform container, which interrupts anything else running against that stack. Only use against a dev stack dedicated to validation. If your container has a name other than `platform`, edit `platform_container` in `config.json`.

Specs are identified by their `<Vendor>/<Product>/<file>.json` path. After bulk runs they're sorted into `specs/{validated,partial,failed}/`. You can drill into a single failure with the bare-path form:

```bash
validate-integration specs/failed/Atlassian/Bitbucket/bitbucket_cloud_2.0.json
```

Exit codes: `0` no failures, `1` at least one FAIL/PARTIAL, `2` setup error.

### From Claude Code

```
/validate-integration /path/to/spec.json
/validate-integration fetch 10
/validate-integration bulk
/validate-integration status
```

## Config

`~/.claude/skills/validate-integration/config.json`:

```json
{
  "iap_url": "http://localhost:3000",
  "username": "admin@itential",
  "password": "admin",
  "default_group": "admin_group",
  "download_path": "$HOME/Downloads",
  "project_root": "<repo>/specs",
  "assets_repo_url": "https://github.com/itential/assets.git",
  "assets_branch": "add-openapi-specs",
  "assets_cache_dir": "$HOME/.cache/itential-assets"
}
```

These are the shared internal dev-stack defaults. Edit if your local setup differs. The file is `chmod 600` and not in git. Re-running `install.sh` migrates older configs in place — your custom values are kept, new keys are filled in.

> **Note on `admin@itential` / `admin`:** these are the documented defaults for a freshly installed Itential dev stack running on `localhost`. They're intended for local use only.

## What this validates

The CLI runs six stages, each producing a ✓ or ✗ in the report:

| Stage | What it checks |
|---|---|
| `login` | Credentials work against `/login` and the resulting cookie authenticates against `/authorization/accounts` |
| `import` | Platform's AJV validation accepts the spec (`POST /integration-models`) |
| `instance` | A codeless `virtual: true` instance can be created from the model |
| `role-discovery` | Platform auto-created an admin role with `provenance == versionId` |
| `authz` | Role is attached to the configured group (idempotent — passes if already attached) |
| `methods` | `role.allowedMethods.length == operations in spec` — the canonical signal that every operation became a callable task |

## What this does NOT validate

- Whether the spec describes the *real* vendor API correctly. Platform validation is structural, not semantic.
- Whether configured auth credentials work against the real upstream. Instance is created with `virtual: true`.
- Whether individual tasks execute end-to-end against a real vendor.

## Repo layout

```
itential-integration-validator/
├── bin/validate-integration                          # the CLI (single + fetch + bulk + status)
├── .claude/skills/validate-integration/SKILL.md      # Claude Code wrapper
├── specs/                                            # managed spec folder (gitignored contents)
│   ├── unvalidated/  validated/  partial/  failed/   # buckets, each shipped via .gitkeep
├── install.sh                                         # one-line installer + config migrator
├── README.md
└── CLAUDE.md                                          # context for Claude in this repo
```

## Troubleshooting

**`command not found: validate-integration`**
`~/.local/bin` isn't on your PATH. Add `export PATH="$HOME/.local/bin:$PATH"` to your shell rc file.

**`Login failed sanity ping` (exit 2)**
Either the dev stack isn't running, the URL in `config.json` is wrong, or the credentials are wrong. Try `curl http://localhost:3000/login -X POST -H "Content-Type: application/json" -d '{"user":{"username":"admin@itential","password":"admin"}}'` to isolate.

**FAIL at `import` with `must NOT have additional properties` on `parse`/`encode`/`encrypt`**
This is an adapter-generated spec (`@itentialopensource/adapter-*`). Strip those non-standard properties from the spec or rewrite it from vendor documentation.

**FAIL at `import` with `exclusiveMinimum must be number`**
Spec uses JSON Schema Draft 4 boolean form (common in older drf-spectacular output like NetBox 4.x). Convert `{ "minimum": N, "exclusiveMinimum": true }` to `{ "exclusiveMinimum": N }` everywhere.

**FAIL at `authz` with `group not found`**
The error message lists available groups. Re-run with `--group <correct_name>`, or update `default_group` in `config.json`.

**`methods X/Y` with X < Y (PARTIAL)**
The platform dropped some operations during import. Almost always due to duplicate or missing `operationId` values. Audit the spec.
