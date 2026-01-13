#!/bin/bash
# Claude Code Haptic Plugin Uninstaller
# Removes haptic feedback hooks for Logitech MX Master 4

set -euo pipefail

HAPTIC_SCRIPT="haptic-trigger.sh"

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

echo "=== Claude Code Haptic Plugin Uninstaller ==="
echo "Detected OS: $OS"
echo ""

# Step 1: Remove haptic trigger script
echo "Removing haptic trigger script..."
if [ -f "$HOOKS_DIR/$HAPTIC_SCRIPT" ]; then
    rm "$HOOKS_DIR/$HAPTIC_SCRIPT"
    echo "  Removed $HOOKS_DIR/$HAPTIC_SCRIPT"
else
    echo "  Script not found (already removed)"
fi

# Step 2: Remove hooks from settings.json
echo "Removing hooks from settings..."
if [ -f "$SETTINGS_FILE" ]; then
    if command -v jq &> /dev/null; then
        # Use jq to remove our specific hooks
        HOOK_PATTERN="haptic-trigger.sh"

        UPDATED_SETTINGS=$(cat "$SETTINGS_FILE" | jq --arg pattern "$HOOK_PATTERN" '
            # Remove Notification hooks containing our script
            if .hooks.Notification then
                .hooks.Notification = [.hooks.Notification[] | select(.hooks | all(.command | contains($pattern) | not))]
            else . end |
            # Remove Stop hooks containing our script
            if .hooks.Stop then
                .hooks.Stop = [.hooks.Stop[] | select(.hooks | all(.command | contains($pattern) | not))]
            else . end |
            # Clean up empty arrays
            if .hooks.Notification == [] then del(.hooks.Notification) else . end |
            if .hooks.Stop == [] then del(.hooks.Stop) else . end |
            # Clean up empty hooks object
            if .hooks == {} then del(.hooks) else . end
        ')

        echo "$UPDATED_SETTINGS" > "$SETTINGS_FILE"
        echo "  Removed haptic hooks from $SETTINGS_FILE"
    else
        echo "  WARNING: jq not found. Please manually remove haptic hooks from $SETTINGS_FILE"
        echo "  Look for entries containing 'haptic-trigger.sh'"
    fi
else
    echo "  Settings file not found (nothing to clean)"
fi

# Step 3: Clean up empty hooks directory
if [ -d "$HOOKS_DIR" ] && [ -z "$(ls -A "$HOOKS_DIR" 2>/dev/null)" ]; then
    rmdir "$HOOKS_DIR"
    echo "  Removed empty hooks directory"
fi

echo ""
echo "=== Uninstallation Complete ==="
echo ""
echo "Haptic feedback hooks have been removed."
echo "Restart Claude Code to apply changes."
