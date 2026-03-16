#!/bin/bash
# Claude Code Haptic Trigger for Logitech MX Master 4
# Triggers haptic feedback when Claude Code events occur.
#
# On Linux: sends HID++ commands directly via /dev/hidraw (no Logi Options+)
# On macOS/Windows: uses HapticWebPlugin HTTP API (requires Logi Options+)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# HapticWebPlugin API endpoint (macOS/Windows fallback)
HAPTIC_API="https://local.jmw.nz:41443/haptic"

# Waveform configuration
WAVEFORM_PERMISSION="knock"      # Attention-grabbing for permission requests
WAVEFORM_IDLE="ringing"          # Gentle reminder for waiting input
WAVEFORM_COMPLETE="completed"    # Satisfying completion feedback
WAVEFORM_QUESTION="jingle"       # Questions/dialogs
WAVEFORM_AUTH="happy_alert"      # Auth success
WAVEFORM_DEFAULT="wave"          # Default for unknown notification types

# Read JSON input from stdin (Claude Code hook input)
INPUT=$(cat)

# Determine the event type and select appropriate waveform
WAVEFORM=""

HOOK_EVENT=$(echo "$INPUT" | grep -o '"hook_event_name"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*: *"\([^"]*\)".*/\1/' || true)

if [ "$HOOK_EVENT" = "Stop" ] || [ "$HOOK_EVENT" = "SubagentStop" ]; then
    WAVEFORM="$WAVEFORM_COMPLETE"
elif [ "$HOOK_EVENT" = "Notification" ]; then
    NOTIFICATION_TYPE=$(echo "$INPUT" | grep -o '"notification_type"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*: *"\([^"]*\)".*/\1/' || true)

    case "$NOTIFICATION_TYPE" in
        permission_prompt)  WAVEFORM="$WAVEFORM_PERMISSION" ;;
        idle_prompt)        WAVEFORM="$WAVEFORM_IDLE" ;;
        elicitation_dialog) WAVEFORM="$WAVEFORM_QUESTION" ;;
        auth_success)       WAVEFORM="$WAVEFORM_AUTH" ;;
        *)                  WAVEFORM="$WAVEFORM_DEFAULT" ;;
    esac
fi

# Trigger haptic feedback if we have a waveform
if [ -n "$WAVEFORM" ]; then
    if [ "$(uname -s)" = "Linux" ] && [ -f "$SCRIPT_DIR/mx4-haptic.py" ]; then
        # Native Linux: HID++ via /dev/hidraw
        python3 "$SCRIPT_DIR/mx4-haptic.py" "$WAVEFORM" >/dev/null 2>&1 || true
    else
        # macOS/Windows/WSL: HapticWebPlugin HTTP API
        curl -s -X POST -d "" "${HAPTIC_API}/${WAVEFORM}" --connect-timeout 2 --max-time 5 >/dev/null 2>&1 || true
    fi
fi

exit 0
