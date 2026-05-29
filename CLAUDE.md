# itential-integration-validator — Claude context

This repo contains a CLI + Claude Code skill that runs the full Itential integration-model validation pipeline against a local dev stack, plus tooling to pull OpenAPI specs in bulk from `github.com/itential/assets` and triage them.

## Architecture

- **`bin/validate-integration`** is the single source of truth. All pipeline logic and subcommand dispatch live there.
- **`.claude/skills/validate-integration/SKILL.md`** is a thin wrapper. It tells Claude which subcommand to invoke and how to present each result type. No procedure logic lives in the skill.
- **`install.sh`** copies the CLI + skill to standard user locations, creates the `specs/` skeleton, and migrates `config.json` (preserves user values, adds new keys). Idempotent.
- **`specs/`** is the managed spec folder. Bucket directories ship in git via `.gitkeep`; actual spec contents are gitignored.

## When editing

- **Pipeline logic changes** → edit `bin/validate-integration` only. Do not duplicate logic into the skill.
- **How Claude presents results** → edit the skill's "Presenting results" section.
- **Config schema changes** → update both the CLI's bootstrap config (`bin/validate-integration` top) and the `DEFAULTS_JSON` in `install.sh` in lockstep. The installer's merge step adds new keys to existing configs.

## Subcommands

| Command | What it does |
|---|---|
| `validate-integration <spec.json>` | Single-spec mode (legacy default). If the spec lives under `specs/`, it's moved into the matching bucket on completion. |
| `validate-integration fetch [<N>\|--all]` | Clones/pulls `github.com/itential/assets` to a cache, copies specs not already in any bucket into `specs/unvalidated/`. |
| `validate-integration bulk` | Validates everything in `specs/unvalidated/`. Prompts once before including already-validated specs (override with `--rerun`/`--no-rerun`). Sorts each spec into validated/partial/failed. |
| `validate-integration status` | Counts per bucket + sample listing. |

## Bucket layout

```
specs/
├── unvalidated/   # freshly fetched, not yet run (or recently moved back here manually)
├── validated/     # last run was PASS — methods count == operation count
├── partial/       # last run was PARTIAL — import succeeded but some ops were dropped
└── failed/        # last run failed at import/instance/role-discovery/authz
```

Specs are identified by their `<Vendor>/<Product>/<file>.json` relative path. The `/OpenAPIs/` directory present in the assets repo is stripped on copy to keep the project tree shallow.

## Pipeline overview (per-spec stages)

| Stage | What it does | Endpoint |
|---|---|---|
| `login` | Log in, sanity-ping an authenticated endpoint | `POST /login` → `GET /authorization/accounts?limit=1` |
| `auth-check` | Verify the spec's `components.securitySchemes` only declares types Itential supports (apiKey / http-basic-or-bearer / oauth2 / mutualTLS / openIdConnect). Pre-flight, no platform call. | (none) |
| `import` | Submit the spec; this is the canonical platform validation | `POST /integration-models` |
| `instance` | Create a `virtual: true` codeless instance. Parse the response and overwrite our derived instance name with whatever the platform actually stored — it doesn't always honor the requested name. | `POST /integrations` |
| `role-discovery` | Find the auto-created admin role keyed by `provenance == versionId`. Paginates with overlapping windows (step=50, limit=100) because the role list endpoint isn't stably ordered between calls. | `GET /authorization/roles?limit=100&skip=N` |
| `authz` | Patch the named group's `assignedRoles` (full-replacement, idempotent) | `PATCH /authorization/groups/{id}` |
| `methods` | Read `role.allowedMethods.length`; compare to operation count in spec | `GET /authorization/roles/{id}` |
| `cleanup` | Optional. Delete the instance then the model, poll the integration-models list until the model is verifiably gone. Auto-created roles are NOT deleted — the platform refuses with "Cannot delete a non-custom role", so they accumulate. | `DELETE /integrations/{name}` → `DELETE /integration-models/{enc-versionId}` |

`methods` count == operation count is the canonical PASS signal. There is no `/apps/list` endpoint on this IAP version — don't try to use one. In bulk mode, login happens once and the token is reused across all per-spec runs.

## Auth conventions (IAP/Pronghorn quirks)

- `POST /login` returns the raw token as the response body, not JSON-wrapped
- Token is sent on subsequent requests as `Cookie: token=<value>` (not `Authorization: Bearer`)
- A "successful" login that returns an error string will pass a length check but fail the sanity ping. Always sanity-ping after login.

## Common spec failure patterns

- Adapter-generated specs (`@itentialopensource/adapter-*`) inject non-standard `parse`/`encode`/`encrypt` schema properties that fail `additionalProperties: false` validation
- NetBox 4.x and older drf-spectacular emit JSON Schema Draft 4 booleans for `exclusiveMinimum`/`exclusiveMaximum` instead of numbers
- Specs with duplicate or missing `operationId` values cause the platform to silently drop those operations, leading to PARTIAL verdicts
