# itential-integration-validator

Validates OpenAPI specs against a local Itential dev stack — confirms every operation becomes a callable task.

> **Use a dedicated local dev stack.** This tool imports and deletes integration models repeatedly. Running it against a shared or production stack will disrupt other work.

## Quick start

**Mac/Linux only.**

```bash
git clone https://github.com/nathaniel-itential/integration-model-validation.git
cd integration-model-validation
./install.sh
$EDITOR ~/.claude/skills/validate-integration/config.json  # set your IAP URL + credentials
validate-integration fetch
validate-integration bulk
```

## What gets installed

| File | Purpose |
|---|---|
| `~/.local/bin/validate-integration` | The CLI |
| `~/.claude/skills/validate-integration/SKILL.md` | Claude Code skill (`/validate-integration`) |
| `~/.claude/skills/validate-integration/config.json` | Connection config |

## Usage

### Fetch + bulk

```bash
validate-integration fetch                  # pull specs from github.com/itential/assets
validate-integration fetch --branch main    # use a specific branch

validate-integration bulk                   # validate all fetched specs
validate-integration bulk --no-cleanup      # keep imported models after each spec
validate-integration bulk --throttle 2      # pause 2s between specs
```

`fetch` writes spec paths to `validate-paths.json` in the current directory.  
`bulk` reads from that file and writes results to `validate-report.json` in the current directory.

### Single spec

```bash
validate-integration <spec.json>
validate-integration <spec.json> --group my_team_group  # override default group
validate-integration <spec.json> --cleanup              # delete instance + model after
validate-integration <spec.json> --json                 # machine-readable output
```

### Platform reset

If a bulk run aborts with a health check failure:

```bash
validate-integration platform-reset
```

Restarts the Docker container and waits until the platform is healthy (~30s). MongoDB and Redis are untouched. If your container isn't named `platform`, set `platform_container` in `config.json`.

### From Claude Code

```
/validate-integration fetch
/validate-integration bulk
/validate-integration /path/to/spec.json
```

## Config

`~/.claude/skills/validate-integration/config.json`:

```json
{
  "iap_url": "http://localhost:3000",
  "username": "admin@itential",
  "password": "admin",
  "default_group": "admin_group",
  "assets_branch": "add-openapi-specs",
  "platform_container": "platform"
}
```

Re-running `install.sh` updates the config in place — your values are preserved.

## Validation stages

| Stage | What it checks |
|---|---|
| `login` | Credentials and connectivity |
| `auth-check` | Security schemes use supported types and are applied to operations |
| `import` | Platform accepts the spec |
| `instance` | A virtual instance can be created from the model |
| `role-discovery` | Platform auto-created an admin role for the integration |
| `authz` | Role is granted to the configured group |
| `methods` | Every operation became a callable task |

## Limitations

- Does not verify the spec matches the real vendor API
- Does not test auth credentials against the real upstream
- Does not execute tasks end-to-end

## Troubleshooting

**`command not found: validate-integration`**  
Add `export PATH="$HOME/.local/bin:$PATH"` to your shell rc file.

**Login failed (exit 2)**  
Check that your dev stack is running and that the URL and credentials in `config.json` are correct.

**FAIL at `auth-check`: auth defined but unapplied**  
The spec defines security schemes but no operations reference them. Add a top-level `security` block.

**FAIL at `import`: must NOT have additional properties**  
Adapter-generated spec with non-standard `parse`/`encode`/`encrypt` fields. Strip them before validating.

**FAIL at `import`: exclusiveMinimum must be number**  
Spec uses JSON Schema Draft 4 boolean syntax. Convert `{ "minimum": N, "exclusiveMinimum": true }` to `{ "exclusiveMinimum": N }`.

**FAIL at `authz`: group not found**  
Re-run with `--group <name>` or set `default_group` in `config.json`. The error output lists available groups.

**PARTIAL (methods X/Y)**  
Some operations were dropped during import. Usually caused by duplicate or missing `operationId` values.
