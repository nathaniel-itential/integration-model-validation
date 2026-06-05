#!/usr/bin/env bash
# install.sh — installs the validate-integration CLI + Claude Code skill.
#
# Usage: clone this repo, then run ./install.sh from inside the clone.
#
# Idempotent: safe to re-run for upgrades. Existing config.json keeps user values
# but gains any newly introduced fields.

set -euo pipefail

# --------- locations ---------
SKILL_DIR="$HOME/.claude/skills/validate-integration"
BIN_DIR="$HOME/.local/bin"
BIN_PATH="$BIN_DIR/validate-integration"
CONFIG_FILE="$BIN_DIR/config.json"

# --------- find sources (must be run from inside the repo) ---------
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || echo "")
if [ -z "$SCRIPT_DIR" ] || [ ! -f "$SCRIPT_DIR/bin/validate-integration" ]; then
  echo "ERROR: install.sh must be run from inside a clone of this repo." >&2
  echo "  git clone <repo-url> && cd <repo> && ./install.sh" >&2
  exit 1
fi
REPO_BASE="$SCRIPT_DIR"
echo "Installing from local clone at $REPO_BASE"

[ -f "$REPO_BASE/bin/validate-integration" ] || { echo "ERROR: bin/validate-integration not found in $REPO_BASE"; exit 1; }
[ -f "$REPO_BASE/.claude/skills/validate-integration/SKILL.md" ] || { echo "ERROR: SKILL.md not found in $REPO_BASE"; exit 1; }

# --------- install CLI ---------
mkdir -p "$BIN_DIR"
install -m 0755 "$REPO_BASE/bin/validate-integration" "$BIN_PATH"
echo "Installed CLI:    $BIN_PATH"

# --------- install skill ---------
mkdir -p "$SKILL_DIR"
install -m 0644 "$REPO_BASE/.claude/skills/validate-integration/SKILL.md" "$SKILL_DIR/SKILL.md"
echo "Installed skill:  $SKILL_DIR/SKILL.md"

# --------- bootstrap / migrate config ---------
# Config lives next to the binary so the script can find it via its own location.
# Migrate from the old ~/.claude/skills location if present and the new one doesn't exist yet.
OLD_CONFIG="$SKILL_DIR/config.json"
if [ ! -f "$CONFIG_FILE" ] && [ -f "$OLD_CONFIG" ]; then
  cp "$OLD_CONFIG" "$CONFIG_FILE"
  chmod 600 "$CONFIG_FILE"
  echo "Migrated config:  $OLD_CONFIG → $CONFIG_FILE"
fi

DEFAULTS_JSON=$(cat <<EOF
{
  "iap_url": "http://localhost:3000",
  "username": "admin@itential",
  "password": "admin",
  "default_group": "admin_group",
  "download_path": "$HOME/Downloads",
  "assets_repo_url": "https://github.com/itential/assets.git",
  "assets_branch": "add-openapi-specs",
  "assets_cache_dir": "$HOME/.cache/itential-assets",
  "platform_container": "platform"
}
EOF
)

if [ ! -f "$CONFIG_FILE" ]; then
  echo "$DEFAULTS_JSON" > "$CONFIG_FILE"
  chmod 600 "$CONFIG_FILE"
  echo "Created config:   $CONFIG_FILE (edit if your dev stack differs)"
else
  # Merge: user values win, but any missing keys get the defaults filled in.
  # Also removes stale keys (e.g. project_root) that no longer exist in the schema.
  MERGED=$(DEFAULTS_JSON="$DEFAULTS_JSON" node -e '
const fs = require("fs");
const defaults = JSON.parse(process.env.DEFAULTS_JSON);
const existing = JSON.parse(fs.readFileSync(process.argv[1], "utf-8"));
// Only keep keys that exist in defaults (drops removed keys like project_root)
const merged = {};
for (const k of Object.keys(defaults)) merged[k] = existing[k] ?? defaults[k];
process.stdout.write(JSON.stringify(merged, null, 2) + "\n");
' "$CONFIG_FILE")
  echo "$MERGED" > "$CONFIG_FILE"
  chmod 600 "$CONFIG_FILE"
  echo "Config updated:   $CONFIG_FILE (user values preserved, missing keys filled)"
fi

# --------- PATH warning ---------
case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *)
    echo ""
    echo "WARNING: $BIN_DIR is not in your PATH."
    echo "Add this to ~/.zshrc or ~/.bashrc:"
    echo "  export PATH=\"\$HOME/.local/bin:\$PATH\""
    ;;
esac

# --------- next steps ---------
echo ""
echo "Done. Try it:"
echo "  validate-integration fetch                             # pull specs from the assets repo"
echo "  validate-integration bulk                             # validate all fetched specs"
echo "  validate-integration /path/to/your/openapi.json      # single spec"
echo ""
echo "Or from Claude Code:"
echo "  /validate-integration fetch"
echo "  /validate-integration bulk"
