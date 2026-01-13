#!/bin/bash
# Claude Code Haptic Plugin Installer
# Installs haptic feedback hooks for Logitech MX Master 4

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HAPTIC_SCRIPT="haptic-trigger.sh"
HAPTIC_API="https://local.jmw.nz:41443"

# Detect operating system
detect_os() {
    case "$(uname -s)" in
        Darwin*)
            OS="macos"
            ;;
        Linux*)
            # Check if running in WSL
            if grep -qEi "(Microsoft|WSL)" /proc/version 2>/dev/null; then
                OS="wsl"
            else
                OS="linux"
            fi
            ;;
        CYGWIN*|MINGW*|MSYS*)
            OS="windows"
            ;;
        *)
            OS="unknown"
            ;;
    esac
    echo "$OS"
}

OS=$(detect_os)

# Set paths based on OS
case "$OS" in
    macos|linux)
        CLAUDE_DIR="$HOME/.claude"
        ;;
    wsl)
        # WSL can use Linux paths
        CLAUDE_DIR="$HOME/.claude"
        ;;
    windows)
        # Git Bash / MSYS2 on Windows
        if [ -n "${USERPROFILE:-}" ]; then
            CLAUDE_DIR="$(cygpath -u "$USERPROFILE")/.claude"
        else
            CLAUDE_DIR="$HOME/.claude"
        fi
        ;;
    *)
        echo "ERROR: Unsupported operating system"
        exit 1
        ;;
esac

HOOKS_DIR="$CLAUDE_DIR/hooks"
SETTINGS_FILE="$CLAUDE_DIR/settings.json"

echo "=== Claude Code Haptic Plugin Installer ==="
echo "Detected OS: $OS"
echo ""

# Step 1: Check for HapticWebPlugin
echo "Checking HapticWebPlugin connectivity..."
if curl -s --connect-timeout 2 --max-time 5 "${HAPTIC_API}/" >/dev/null 2>&1; then
    echo "  HapticWebPlugin is running"
else
    echo ""
    echo "WARNING: HapticWebPlugin is not responding at ${HAPTIC_API}"
    echo ""
    echo "Please install HapticWebPlugin first:"
    echo ""
    echo "  The plugin is included in this repository at: $SCRIPT_DIR/plugin/HapticWeb.lplug4"
    echo "  Source: https://github.com/Fallstop/HapticWebPlugin"
    echo ""
    echo "  Installation steps:"
    echo "    1. Open Logitech Options+ and click on your MX Master 4"
    echo "    2. In the left sidebar, open the HAPTIC FEEDBACK tab"
    echo "    3. Click on the haptic feedback settings popover"
    echo "    4. In the right sidebar, click INSTALL AND UNINSTALL PLUGINS"
    echo "    5. Double-click the file: $SCRIPT_DIR/plugin/HapticWeb.lplug4"
    echo "    6. Return to Logitech Options+ and press Continue"
    echo "    7. Run this installer again"
    echo ""
    read -p "Continue anyway? (y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo "Installation cancelled."
        exit 1
    fi
fi

# Step 2: Create hooks directory
echo "Creating hooks directory..."
mkdir -p "$HOOKS_DIR"
echo "  Created $HOOKS_DIR"

# Step 3: Copy haptic trigger script
echo "Installing haptic trigger script..."
cp "$SCRIPT_DIR/scripts/$HAPTIC_SCRIPT" "$HOOKS_DIR/$HAPTIC_SCRIPT"
chmod +x "$HOOKS_DIR/$HAPTIC_SCRIPT"
echo "  Installed $HOOKS_DIR/$HAPTIC_SCRIPT"

# Step 4: Configure Claude Code hooks
echo "Configuring Claude Code hooks..."

# Create settings.json if it doesn't exist
if [ ! -f "$SETTINGS_FILE" ]; then
    echo '{}' > "$SETTINGS_FILE"
    echo "  Created $SETTINGS_FILE"
fi

# Check if jq is available for JSON manipulation
if command -v jq &> /dev/null; then
    # Use jq for proper JSON merging
    HOOK_COMMAND="$HOOKS_DIR/$HAPTIC_SCRIPT"

    # Create the new hooks configuration (no matcher = catch ALL notifications)
    NEW_HOOKS=$(cat <<EOF
{
  "Notification": [
    {
      "hooks": [
        {
          "type": "command",
          "command": "$HOOK_COMMAND"
        }
      ]
    }
  ],
  "Stop": [
    {
      "hooks": [
        {
          "type": "command",
          "command": "$HOOK_COMMAND"
        }
      ]
    }
  ]
}
EOF
)

    # Merge hooks into existing settings
    CURRENT_SETTINGS=$(cat "$SETTINGS_FILE")

    # Check if hooks already exist
    if echo "$CURRENT_SETTINGS" | jq -e '.hooks' >/dev/null 2>&1; then
        # Merge with existing hooks
        UPDATED_SETTINGS=$(echo "$CURRENT_SETTINGS" | jq --argjson new_hooks "$NEW_HOOKS" '
            .hooks.Notification = ($new_hooks.Notification + (.hooks.Notification // [])) |
            .hooks.Stop = ($new_hooks.Stop + (.hooks.Stop // []))
        ')
    else
        # Add hooks key
        UPDATED_SETTINGS=$(echo "$CURRENT_SETTINGS" | jq --argjson new_hooks "$NEW_HOOKS" '.hooks = $new_hooks')
    fi

    echo "$UPDATED_SETTINGS" > "$SETTINGS_FILE"
    echo "  Updated $SETTINGS_FILE with hooks configuration"
else
    # Fallback: Create/overwrite with simple configuration
    HOOK_COMMAND="$HOOKS_DIR/$HAPTIC_SCRIPT"

    cat > "$SETTINGS_FILE" <<EOF
{
  "hooks": {
    "Notification": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "$HOOK_COMMAND"
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "$HOOK_COMMAND"
          }
        ]
      }
    ]
  }
}
EOF
    echo "  Created $SETTINGS_FILE with hooks configuration"
    echo "  NOTE: jq not found. Previous settings were overwritten."
    case "$OS" in
        macos)
            echo "        Install jq for proper JSON merging: brew install jq"
            ;;
        linux|wsl)
            echo "        Install jq for proper JSON merging: sudo apt install jq  OR  sudo dnf install jq"
            ;;
        windows)
            echo "        Install jq for proper JSON merging: choco install jq  OR  scoop install jq"
            ;;
    esac
fi

# Step 5: Test haptic feedback
echo ""
echo "Testing haptic feedback..."
if curl -s -X POST -d "" "${HAPTIC_API}/haptic/completed" --connect-timeout 2 --max-time 5 >/dev/null 2>&1; then
    echo "  Haptic test successful! You should have felt a vibration."
else
    echo "  Haptic test skipped (HapticWebPlugin not responding)"
fi

echo ""
echo "=== Installation Complete ==="
echo ""
echo "Next steps:"
echo "  1. Restart Claude Code to load the new hooks"
echo "  2. When Claude finishes a task or needs input, your mouse will vibrate!"
echo ""
echo "To uninstall, run: $SCRIPT_DIR/uninstall.sh"
