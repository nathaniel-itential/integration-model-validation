#!/usr/bin/env bash
# install.sh — installs the validate-integration CLI + Claude Code skill.
#
# Standalone usage (inside a clone of this repo):
#   ./install.sh
#
# One-line usage (after the repo is on an internal git host):
#   curl -fsSL https://gitlab.com/itential/itential-integration-validator/-/raw/main/install.sh | bash
#
# Idempotent: safe to re-run for upgrades. Existing config.json is never overwritten.

set -euo pipefail

# --------- locations ---------
SKILL_DIR="$HOME/.claude/skills/validate-integration"
BIN_DIR="$HOME/.local/bin"
BIN_PATH="$BIN_DIR/validate-integration"

REPO_BASE="${INTEGRATION_VALIDATOR_REPO:-}"

# --------- find or fetch sources ---------
if [ -z "$REPO_BASE" ]; then
  # Detect if we're being run from a clone of the repo
  SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || echo "")
  if [ -n "$SCRIPT_DIR" ] && [ -f "$SCRIPT_DIR/bin/validate-integration" ]; then
    REPO_BASE="$SCRIPT_DIR"
    echo "Installing from local clone at $REPO_BASE"
  else
    # Curl-piped install: clone to a temp dir
    REPO_URL="${INTEGRATION_VALIDATOR_GIT:-git@gitlab.com:itential/itential-integration-validator.git}"
    TMP=$(mktemp -d)
    trap 'rm -rf "$TMP"' EXIT
    echo "Cloning $REPO_URL to $TMP..."
    git clone --depth 1 "$REPO_URL" "$TMP/repo" >/dev/null
    REPO_BASE="$TMP/repo"
  fi
fi

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

# --------- bootstrap config if missing ---------
CONFIG_FILE="$SKILL_DIR/config.json"
if [ ! -f "$CONFIG_FILE" ]; then
  cat > "$CONFIG_FILE" <<'EOF'
{
  "iap_url": "http://localhost:3000",
  "username": "admin@itential",
  "password": "admin",
  "default_group": "admin_group"
}
EOF
  chmod 600 "$CONFIG_FILE"
  echo "Created config:   $CONFIG_FILE (edit if your dev stack differs)"
else
  echo "Config exists:    $CONFIG_FILE (left untouched)"
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
echo "  validate-integration /path/to/your/openapi.json"
echo ""
echo "Or from Claude Code:"
echo "  /validate-integration /path/to/your/openapi.json"
