---
name: validate-integration
description: Run the full Itential integration-model validation pipeline against a local dev stack — imports an OpenAPI spec, creates the instance, grants the auto-created role to a group, and confirms every operation became a callable task. Replaces the manual import → create → authorize → open Studio → check sidebar workflow. Use when the user wants to verify an OpenAPI spec produces a working integration without manually clicking through the UI.
argument-hint: "<path-to-openapi-spec.json> [--cleanup] [--group <groupName>] [--json]"
---

# Integration Model Validation

This skill is a thin wrapper around the `validate-integration` CLI installed at `~/.local/bin/validate-integration` (or wherever `install.sh` put it). The CLI does all the real work; the skill just invokes it and presents the result to the user.

## Prerequisites

- `validate-integration` is on the user's `PATH`. If `command -v validate-integration` returns nothing, the user needs to run the project's `install.sh`.
- The local IAP dev stack is running and reachable (the CLI's first call will fail clearly if not).
- A config file exists at `~/.claude/skills/validate-integration/config.json`. The CLI auto-creates it with shared dev-stack defaults on first run; only edit if the user's setup differs.

## Procedure

Use the Bash tool to invoke the CLI directly with whatever arguments the user provided:

```bash
validate-integration <spec-path> [--cleanup] [--group <name>] [--json]
```

The CLI prints a human-readable report on stdout (or JSON with `--json`) and exits with:
- `0` = PASS
- `1` = FAIL or PARTIAL (some operations dropped during import, etc.)
- `2` = setup error (missing config, dev stack unreachable, login failure)

## Presenting results

The CLI's report is already user-facing. Just relay it verbatim, then add a short interpretation:

- **PASS** — say "All N operations became callable tasks. The integration is ready to use in workflows."
- **PARTIAL** (`methods` stage shows `X/Y` with X < Y) — say "The platform imported the spec but dropped (Y-X) operations. Most common cause: duplicate or missing `operationId` values. Look for adapter-generated specs (which often have `ph_request_type` enum leaks) or hand-written specs that reuse operationIds across paths."
- **FAIL at `import`** — the platform's AJV validation rejected the spec. The CLI surfaces the first AJV error in the stage's `detail`. Common patterns to mention if relevant:
  - `must NOT have additional properties` on `parse`/`encode`/`encrypt` → adapter-generated spec (Slack-family). Tell the user the spec was probably generated from an `@itentialopensource/adapter-*` package and needs the non-standard fields stripped.
  - `exclusiveMinimum must be number` → JSON Schema Draft 4 boolean form. Common in older drf-spectacular output (NetBox 4.x). Needs the boolean form converted to numbers.
- **FAIL at `authz`** with "group not found" — the CLI lists available groups in the error. Suggest re-running with `--group <correct_name>`, or editing `default_group` in `config.json`.
- **FAIL at `login`** — usually wrong credentials or wrong URL. Tell the user to check `~/.claude/skills/validate-integration/config.json`.

## What this skill does NOT verify

These are out of scope by design — call them out if the user asks:

- Whether the spec describes the *real* vendor API correctly. Platform validation is structural, not semantic. A spec can PASS this pipeline and still describe fields the real vendor doesn't have.
- Whether the configured auth credentials work against the real upstream. Instance creation uses `virtual: true` and no real upstream credentials.
- Whether individual tasks execute end-to-end. For that, suggest the user build a workflow with one of the tasks and run it via Operations Manager.

## When NOT to use this skill

- The user just wants to check OpenAPI structural validity without touching the platform → suggest the standalone `iap-validate` CLI instead.
- The user wants to test a spec against a live vendor (real Slack, real Jira) → this skill creates a `virtual: true` instance that doesn't connect anywhere by default.
- The user wants to inspect or modify spec internals → this is a validator, not an editor.
