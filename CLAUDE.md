# itential-integration-validator — Claude context

This repo contains a CLI + Claude Code skill that runs the full Itential integration-model validation pipeline against a local dev stack, plus tooling to index and bulk-validate OpenAPI specs from a configured local folder.

## Architecture

- **`bin/validate-integration`** is the single source of truth. All pipeline logic and subcommand dispatch live there.
- **`.claude/skills/validate-integration/SKILL.md`** is a thin wrapper. It tells Claude which subcommand to invoke and how to present each result type. No procedure logic lives in the skill.
- **`install.sh`** copies the CLI + skill to standard user locations and migrates `config.json` (preserves user values, adds new keys, removes stale keys). Idempotent.

## When editing

- **Pipeline logic changes** → edit `bin/validate-integration` only. Do not duplicate logic into the skill.
- **How Claude presents results** → edit the skill's "Presenting results" section.
- **Config schema changes** → update both the CLI's bootstrap config (`bin/validate-integration` top) and the `DEFAULTS_JSON` in `install.sh` in lockstep. The installer's merge step adds new keys and removes stale ones.

## Subcommands

| Command | What it does |
|---|---|
| `validate-integration <spec.json>` | Single-spec mode. Validates one spec and prints a full stage-by-stage report. |
| `validate-integration fetch` | Scans the `assets_dir` folder (configured in `config.json`) for `*.json` files one level deep and writes their absolute paths to `validate-paths.json` in the current working directory. |
| `validate-integration bulk` | Reads paths from `validate-paths.json` (written by `fetch`), validates each spec, prints progress to the terminal, and writes a full JSON report to `validate-report.json` in the same directory. |

## Output files (written to the current working directory)

| File | Written by | Contents |
|---|---|---|
| `validate-paths.json` | `fetch` | JSON array of absolute paths to all discovered specs |
| `validate-report.json` | `bulk` | JSON report: timestamp, summary counts, per-spec verdict + failure detail |

## Pipeline overview (per-spec stages)

| Stage | What it does | Endpoint |
|---|---|---|
| `login` | Log in, sanity-ping an authenticated endpoint | `POST /login` → `GET /authorization/accounts?limit=1` |
| `auth-check` | Verify the spec's `components.securitySchemes` only declares supported types (apiKey / http-basic-or-bearer / oauth2 / mutualTLS / openIdConnect) AND that at least one scheme is applied to operations. Pre-flight, no platform call. | (none) |
| `import` | Submit the spec; this is the canonical platform validation | `POST /integration-models` |
| `instance` | Create a `virtual: true` codeless instance. Parse the response and overwrite our derived instance name with whatever the platform actually stored — it doesn't always honor the requested name. | `POST /integrations` |
| `role-discovery` | Find the auto-created admin role keyed by `provenance == versionId`. Paginates with `?sort=_id&order=1` for deterministic ordering. | `GET /authorization/roles?sort=_id&order=1&limit=100&skip=N` |
| `authz` | Patch the named group's `assignedRoles` (idempotent) | `PATCH /authorization/groups/{id}` |
| `methods` | Read `role.allowedMethods.length`; compare to operation count in spec | `GET /authorization/roles/{id}` |
| `cleanup` | Default in bulk. Delete the instance then the model, poll until verifiably gone. Auto-created roles are NOT deleted — the platform refuses with "Cannot delete a non-custom role". | `DELETE /integrations/{name}` → `DELETE /integration-models/{enc-versionId}` |

`methods` count == operation count is the canonical PASS signal. In bulk mode, login happens once and the token is reused across all per-spec runs.

## Auth conventions (IAP/Pronghorn quirks)

- `POST /login` returns the raw token as the response body, not JSON-wrapped
- Token is sent on subsequent requests as `Cookie: token=<value>` (not `Authorization: Bearer`)
- A "successful" login that returns an error string will pass a length check but fail the sanity ping. Always sanity-ping after login.

## Common spec failure patterns

- Adapter-generated specs (`@itentialopensource/adapter-*`) inject non-standard `parse`/`encode`/`encrypt` schema properties that fail `additionalProperties: false` validation
- NetBox 4.x and older drf-spectacular emit JSON Schema Draft 4 booleans for `exclusiveMinimum`/`exclusiveMaximum` instead of numbers
- Specs with duplicate or missing `operationId` values cause the platform to silently drop those operations, leading to PARTIAL verdicts
- Specs that define `securitySchemes` but have no top-level `security` block and no per-operation `security` fields send unauthenticated requests at runtime
