# itential-integration-validator

End-to-end validator for OpenAPI specs intended for Itential integration models. Replaces the manual workflow of: import → create integration → grant role to group → open Studio → check the task palette.

One command tells you whether a spec produces a working set of callable tasks.

## Quick start

```bash
# 1. Install (requires git access to this repo)
curl -fsSL https://gitlab.com/itential/itential-integration-validator/-/raw/main/install.sh | bash

# 2. Edit config if your dev stack differs from defaults
$EDITOR ~/.claude/skills/validate-integration/config.json

# 3. Make sure your IAP dev stack is running

# 4. Validate a spec
validate-integration /path/to/openapi.json
```

You'll get a PASS/PARTIAL/FAIL verdict with per-stage diagnostics in one screen.

## What gets installed

| File | Purpose |
|---|---|
| `~/.local/bin/validate-integration` | The CLI — does all the work |
| `~/.claude/skills/validate-integration/SKILL.md` | Claude Code skill — invokes the CLI when you type `/validate-integration` |
| `~/.claude/skills/validate-integration/config.json` | Dev stack URL + credentials + default group (created on first run, never overwritten) |

## Usage

### From a terminal

```bash
validate-integration <spec.json>                            # default group from config
validate-integration <spec.json> --group my_team_group      # override group
validate-integration <spec.json> --cleanup                  # delete instance + model after
validate-integration <spec.json> --json                     # machine-readable output
```

Exit codes: `0` PASS, `1` FAIL/PARTIAL, `2` setup error.

### From Claude Code

```
/validate-integration /path/to/spec.json
```

Or in natural language: "use validate-integration on `/path/to/spec.json`."

## Config

`~/.claude/skills/validate-integration/config.json`:

```json
{
  "iap_url": "http://localhost:3000",
  "username": "admin@itential",
  "password": "admin",
  "default_group": "admin_group"
}
```

These are the shared internal dev-stack defaults. Edit if your local setup differs. The file is `chmod 600` and not in git.

### A note on the credentials in this repo

`admin@itential` / `admin` appear as literal values in `bin/validate-integration`, `install.sh`, and this README. These are the **publicly documented default credentials for a freshly installed Itential dev stack** — not production secrets. The dev stack runs locally on `localhost:3000`, has no external network exposure, and exists solely for developer testing.

This tool is designed to work *only* against that dev stack. If your organization has changed the defaults or is targeting a different stack, edit `~/.claude/skills/validate-integration/config.json` after install. Automated secret scanners may flag these values; they are intentional and acceptable for this tool's scope.

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

For vendor-accuracy testing, layer this with a Prism mock + a real-vendor smoke call on critical endpoints.

## Repo layout

```
itential-integration-validator/
├── bin/validate-integration                          # the CLI
├── .claude/skills/validate-integration/SKILL.md      # Claude Code wrapper
├── install.sh                                         # one-line installer
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
