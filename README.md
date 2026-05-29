# itential-integration-validator

End-to-end validator for OpenAPI specs intended for Itential integration models. Replaces the manual workflow of: import → create integration → grant role to group → open Studio → check the task palette.

One command tells you whether a spec will successfully import into IAP, and the tasks populate in Studio. 
This DOES NOT check for task structure/shape, nor does it validate authentication. 

## Quick start

```bash
# 1. Clone the repo
gh repo clone nathaniel-itential/integration-model-validation
cd integration-model-validation

# 2. Run the install script
./install.sh

# 3. Edit config if your dev stack differs from defaults:
$EDITOR ~/.claude/skills/validate-integration/config.json

# 4. Start your IAP platform (this tool is built against itential-dev-stack)

# 5. Validate a spec
validate-integration openapi.json
```

This tool is designed to run against [itential-dev-stack](https://github.com/itential/itential-dev-stack) as the primary supported platform.

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
  "default_group": "admin_group",
  "download_path": "/Users/<you>/Downloads"
}
```

These are the shared internal dev-stack defaults. Edit if your local setup differs. The file is `chmod 600` and not in git.

### `download_path` — pass bare filenames

When set, you can drop the directory prefix on specs you keep there:

```bash
validate-integration example.json                  # looks for $DOWNLOAD_PATH/example.json
validate-integration ./local/file.json             # absolute/relative paths still work as-is
validate-integration /Users/me/Downloads/foo.json  # fully-qualified paths still work
```

Path resolution: the CLI first tries the path you gave (so absolute and relative-to-cwd both work). If that doesn't exist AND `download_path` is set, it tries `<download_path>/<your-arg>`. Fails clearly listing both attempts if nothing matches.

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
