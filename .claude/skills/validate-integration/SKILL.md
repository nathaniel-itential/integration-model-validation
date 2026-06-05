---
name: validate-integration
description: Run the full Itential integration-model validation pipeline against a local dev stack — imports an OpenAPI spec, creates the instance, grants the auto-created role to a group, and confirms every operation became a callable task. Also pulls OpenAPI specs from the itential/assets repo for bulk validation. Replaces the manual import → create → authorize → open Studio → check sidebar workflow. Use when the user wants to verify an OpenAPI spec produces a working integration without manually clicking through the UI.
argument-hint: "<spec.json> [flags]  |  fetch [--branch <name>]  |  bulk [--no-cleanup] [--throttle <s>]"
---

# Integration Model Validation

This skill is a thin wrapper around the `validate-integration` CLI installed at `~/.local/bin/validate-integration` (via `install.sh`). The CLI does all the real work; the skill just invokes it and presents results.

## Prerequisites

- `validate-integration` is on the user's `PATH`. If `command -v validate-integration` returns nothing, the user needs to run the project's `install.sh`.
- The local IAP dev stack is running and reachable (only needed for single/bulk modes; `fetch` doesn't touch the dev stack).
- A config file exists at `~/.local/bin/config.json` (next to the installed binary). `install.sh` creates and migrates it; only edit if the user's setup differs from the team defaults.

## Subcommands

```bash
validate-integration <spec.json> [--cleanup] [--group <name>] [--json]   # single spec
validate-integration fetch [--branch <name>]                              # pull specs from the assets repo
validate-integration bulk [--no-cleanup] [--throttle <s>] [--group <name>]
```

The CLI exits with:
- `0` = PASS (single) or no failures (bulk/fetch)
- `1` = at least one spec FAILed or was PARTIAL
- `2` = setup error (missing config, dev stack unreachable, login failure, bad args)

### Picking the right subcommand

| User intent | Command |
|---|---|
| "validate this spec at /path/to/foo.json" | `validate-integration /path/to/foo.json` |
| "pull specs from the assets repo" | `validate-integration fetch` |
| "validate all fetched specs" | `validate-integration bulk` |

## Procedure per subcommand

### Single spec
Invoke the CLI with whatever path the user provided.

### fetch
Just run it. The CLI clones/pulls a cached copy of `github.com/itential/assets` (branch configured in `config.json`) and writes all discovered spec paths to `validate-paths.json` in the current working directory. Print the count and path written.

### bulk
Run it. The CLI reads paths from `validate-paths.json` (written by `fetch`), validates each spec, prints one progress line per spec to the terminal, and writes a full JSON report to `validate-report.json` in the current working directory.

Bulk cleans up each imported model + instance after validating by default — pass `--no-cleanup` to keep them. Between specs, bulk runs a platform health check. If the dev stack stops responding mid-batch, bulk aborts cleanly with a progress summary. Suggest bumping `--throttle` to 1–3 if the user reports import HTTP 404 or HTTP 000 errors mid-run.

After bulk completes, the JSON report at `validate-report.json` contains the full results. If `FAIL > 0`, offer to dig into a specific failed spec by running it in single-spec mode for the full stage-by-stage report.

## Presenting results

### Single-spec verdicts
- **PASS** — "All N operations became callable tasks. The integration is ready to use in workflows."
- **PARTIAL** (`methods` stage shows `X/Y` with X < Y) — "The platform imported the spec but dropped (Y-X) operations. Most common cause: duplicate or missing `operationId` values."
- **FAIL at `auth-check`** — two possible causes, both in the stage detail:
  - *Unsupported type* — a scheme uses a type Itential doesn't support. Supported: `apiKey`, `http` (with `basic` or `bearer`), `oauth2`, `mutualTLS`, `openIdConnect`. Suggest removing or replacing the offending scheme.
  - *Auth defined but unapplied* — all defined schemes are supported but none are applied to any operation. The integration would import but send unauthenticated requests at runtime. Fix: add a top-level `security` block referencing the correct scheme(s).
- **FAIL at `import`** — first AJV error is in the stage detail. Common patterns:
  - `must NOT have additional properties` on `parse`/`encode`/`encrypt` → adapter-generated spec. Strip non-standard fields.
  - `exclusiveMinimum must be number` → JSON Schema Draft 4 boolean form (NetBox 4.x, older drf-spectacular). Convert to number form.
- **FAIL at `authz`** with "group not found" — error lists available groups. Suggest `--group <correct>` or edit `default_group` in `config.json`.
- **FAIL at `login`** — wrong credentials or URL. Tell the user to check `~/.local/bin/config.json`.

### Bulk verdicts
The CLI prints one line per spec with `[✓]` (pass), `[~]` (partial), `[✗]` (fail), then a summary and the path to `validate-report.json`. Highlight any failures and offer to re-run a specific failed spec in single-spec mode for the full report.

### When a bulk run has many failures
Group failures by stage if there are >3. Each failure line shows `FAIL @<stage>: <detail>` — bucket them by stage to identify systemic issues vs. one-off problems. Then ask the user which class to dig into first.

## What this skill does NOT verify

- Whether the spec describes the *real* vendor API correctly. Platform validation is structural, not semantic.
- Whether the configured auth credentials work against the real upstream. Instance creation uses `virtual: true`.
- Whether individual tasks execute end-to-end. For that, suggest building a workflow in Operations Manager.

## When NOT to use this skill

- The user wants to test a spec against a live vendor → this creates a `virtual: true` instance that doesn't connect anywhere.
- The user wants to inspect or modify spec internals → this is a validator, not an editor.
