# itential-integration-validator — Claude context

This repo contains a single tool: a CLI + Claude Code skill that runs the full Itential integration-model validation pipeline against a local dev stack.

## Architecture

- **`bin/validate-integration`** is the single source of truth. All pipeline logic lives there.
- **`.claude/skills/validate-integration/SKILL.md`** is a thin wrapper. It tells Claude to invoke the CLI and present results. No procedure logic lives in the skill.
- **`install.sh`** copies both to standard user locations (`~/.local/bin/`, `~/.claude/skills/`). Idempotent; safe to re-run.

## When editing

- **Pipeline logic changes** → edit `bin/validate-integration` only. Do not duplicate logic into the skill.
- **How Claude presents results** → edit the skill's "Presenting results" section.
- **Config schema changes** → update both the CLI's bootstrap config and the SKILL.md/README.md mentions in lockstep.

## Pipeline overview

| Stage | What it does | Endpoint |
|---|---|---|
| `login` | Log in, sanity-ping an authenticated endpoint | `POST /login` → `GET /authorization/accounts?limit=1` |
| `import` | Submit the spec; this is the canonical platform validation | `POST /integration-models` |
| `instance` | Create a `virtual: true` codeless instance | `POST /integrations` |
| `role-discovery` | Find the auto-created admin role keyed by `provenance == versionId` | `GET /authorization/roles?limit=500` |
| `authz` | Patch the named group's `assignedRoles` (full-replacement, idempotent) | `PATCH /authorization/groups/{id}` |
| `methods` | Read `role.allowedMethods.length`; compare to operation count in spec | `GET /authorization/roles/{id}` |

`methods` count == operation count is the canonical PASS signal. There is no `/apps/list` endpoint on this IAP version — don't try to use one.

## Auth conventions (IAP/Pronghorn quirks)

- `POST /login` returns the raw token as the response body, not JSON-wrapped
- Token is sent on subsequent requests as `Cookie: token=<value>` (not `Authorization: Bearer`)
- A "successful" login that returns an error string will pass a length check but fail the sanity ping. Always sanity-ping after login.

## Common spec failure patterns

- Adapter-generated specs (`@itentialopensource/adapter-*`) inject non-standard `parse`/`encode`/`encrypt` schema properties that fail `additionalProperties: false` validation
- NetBox 4.x and older drf-spectacular emit JSON Schema Draft 4 booleans for `exclusiveMinimum`/`exclusiveMaximum` instead of numbers
- Specs with duplicate or missing `operationId` values cause the platform to silently drop those operations, leading to PARTIAL verdicts
