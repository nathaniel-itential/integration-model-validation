---
name: validate-integration
description: Run the full Itential integration-model validation pipeline against a local dev stack — imports an OpenAPI spec, creates the instance, grants the auto-created role to a group, and confirms every operation became a callable task. Also pulls OpenAPI specs from the itential/assets repo for bulk validation. Replaces the manual import → create → authorize → open Studio → check sidebar workflow. Use when the user wants to verify an OpenAPI spec produces a working integration without manually clicking through the UI.
argument-hint: "<spec.json> [flags]  |  fetch [<N>|--all]  |  bulk [--rerun|--no-rerun]  |  status"
---

# Integration Model Validation

This skill is a thin wrapper around the `validate-integration` CLI installed at `~/.local/bin/validate-integration` (via `install.sh`). The CLI does all the real work; the skill just invokes it and presents results.

## Prerequisites

- `validate-integration` is on the user's `PATH`. If `command -v validate-integration` returns nothing, the user needs to run the project's `install.sh`.
- The local IAP dev stack is running and reachable (only needed for single/bulk modes; `fetch` and `status` don't touch the dev stack).
- A config file exists at `~/.claude/skills/validate-integration/config.json`. `install.sh` creates and migrates it; only edit if the user's setup differs from the team defaults.

## Subcommands

```bash
validate-integration <spec.json> [--cleanup] [--group <name>] [--json]      # single spec
validate-integration fetch [<N> | --all] [--branch <name>]                  # pull specs from the assets repo
validate-integration bulk [--rerun | --no-rerun] [--no-cleanup] [--throttle <s>] [--group <name>] [--json]
validate-integration status [--json]
validate-integration clear [--all | --unvalidated | --validated | --partial | --failed] [--yes]
```

The CLI exits with:
- `0` = PASS (single) or no failures (bulk/fetch/status)
- `1` = at least one spec FAILed or was PARTIAL
- `2` = setup error (missing config, dev stack unreachable, login failure, bad args)

### Picking the right subcommand

| User intent | Command |
|---|---|
| "validate this spec at /path/to/foo.json" | `validate-integration /path/to/foo.json` |
| "pull N new specs from the repo" | `validate-integration fetch <N>` |
| "pull every spec we don't have yet" | `validate-integration fetch --all` |
| "validate everything I haven't validated yet" | `validate-integration bulk` |
| "what's the state of my spec folder?" | `validate-integration status` |
| "delete local specs to start over" | `validate-integration clear --all` (or specific buckets) |

The managed spec folder is `specs/` inside the repo (gitignored). Specs are sorted into `unvalidated/`, `validated/`, `partial/`, `failed/` after each run. Bare-path mode (single) leaves outside-folder specs in place; specs that already live under `specs/` get moved into the matching bucket on completion.

## Procedure per subcommand

### Single spec
Invoke the CLI with whatever path the user provided. If the user passes a spec already in `validated/` or `partial/`, the CLI prompts interactively; pass `--force` to skip the prompt.

### fetch
Just run it. The CLI clones/pulls a cached copy of `github.com/itential/assets` (branch `add-openapi-specs` by default) and copies any specs not already in the project folder into `specs/unvalidated/`. Print the CLI's "+ <path>" list verbatim.

### bulk
Run it as the user asked. The CLI prompts once if there are already-validated specs; if running non-interactively, default is "don't re-run." User can pass `--rerun` to force re-run of validated specs, or `--no-rerun` to skip the prompt and only do unvalidated. Bulk cleans up each imported model + instance after validating (since accumulating many of them slows the platform down) — pass `--no-cleanup` to keep them around.

Between specs, bulk sleeps `--throttle <seconds>` (default 1) and runs a platform health check. If the dev stack stops responding mid-batch, bulk aborts cleanly with a summary of how many were validated so far — instead of marching through the rest as misleading per-spec failures. Suggest bumping `--throttle` to 2–3 if a user reports import HTTP 404 or HTTP 000 errors mid-run.

After bulk, look at the summary line counts. If `FAIL > 0`, offer to dig into a specific failed spec: `validate-integration specs/failed/<path>` re-runs it with the full report. If the run ABORTED (exit 2 with "Bulk aborted"), the platform itself is the issue, not the specs — recommend restarting the dev stack before continuing.

### status
Trivial — just shows bucket counts and a sample listing per bucket.

### clear
Deletes local spec files from one or more buckets. The CLI prints a per-bucket count and prompts before deleting; pass `--yes` for non-interactive use. `clear` only touches the local file tree — imported models on the IAP stack are not affected (use `bulk --cleanup` to tear those down, or delete them in the platform UI).

## Presenting results

The CLI's report is user-facing. Relay it verbatim, then add a short interpretation:

### Single-spec verdicts
- **PASS** — "All N operations became callable tasks. The integration is ready to use in workflows."
- **PARTIAL** (`methods` stage shows `X/Y` with X < Y) — "The platform imported the spec but dropped (Y-X) operations. Most common cause: duplicate or missing `operationId` values."
- **FAIL at `auth-check`** — the spec's `components.securitySchemes` uses a type Itential doesn't support. Supported types: `apiKey`, `http` (with `basic` or `bearer`), `oauth2`, `mutualTLS`, `openIdConnect`. The stage detail names the offending scheme. Suggest the user either remove the unsupported scheme or replace it with a supported one (most often `http`/`bearer` is the right substitute).
- **FAIL at `import`** — first AJV error is in the stage detail. Common patterns:
  - `must NOT have additional properties` on `parse`/`encode`/`encrypt` → adapter-generated spec (`@itentialopensource/adapter-*`). Non-standard schema fields need to be stripped.
  - `exclusiveMinimum must be number` → JSON Schema Draft 4 boolean form (NetBox 4.x and older drf-spectacular output). Convert boolean form to numbers.
- **FAIL at `authz`** with "group not found" — error lists available groups. Suggest `--group <correct>` or edit `default_group` in `config.json`.
- **FAIL at `login`** — wrong credentials or URL. Tell the user to check `~/.claude/skills/validate-integration/config.json`.

### Bulk verdicts
The CLI prints one line per spec with `[✓]` (pass), `[~]` (partial), `[✗]` (fail), followed by a summary. Highlight any failures and offer to investigate the top one. If everything passed, mention that all specs are now in `specs/validated/` and ready to be used as integration models.

### When a bulk run has many failures
Group failures by stage if there are >3 (most useful breakdown). Each failure line shows `FAIL @<stage>: <detail>` — you can `grep` the output to bucket them. Then ask the user which class to dig into first.

## What this skill does NOT verify

- Whether the spec describes the *real* vendor API correctly. Platform validation is structural, not semantic.
- Whether the configured auth credentials work against the real upstream. Instance creation uses `virtual: true`.
- Whether individual tasks execute end-to-end. For that, suggest building a workflow in Operations Manager.

## When NOT to use this skill

- The user just wants to check OpenAPI structural validity without touching the platform → suggest the standalone `iap-validate` CLI instead.
- The user wants to test a spec against a live vendor → this creates a `virtual: true` instance that doesn't connect anywhere.
- The user wants to inspect or modify spec internals → this is a validator, not an editor.
