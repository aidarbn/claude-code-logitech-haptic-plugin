#!/bin/bash
# Claude Code Haptic Trigger for Logitech MX Master 4
# Triggers haptic feedback via HapticWebPlugin when Claude Code events occur

set -euo pipefail

# HapticWebPlugin API endpoint
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

# Check for hook_event_name (identifies the hook type)
HOOK_EVENT=$(echo "$INPUT" | grep -o '"hook_event_name"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*: *"\([^"]*\)".*/\1/' || true)

if [ "$HOOK_EVENT" = "Stop" ] || [ "$HOOK_EVENT" = "SubagentStop" ]; then
    # Task completed
    WAVEFORM="$WAVEFORM_COMPLETE"
elif [ "$HOOK_EVENT" = "Notification" ]; then
    # Check notification_type for more specific handling
    NOTIFICATION_TYPE=$(echo "$INPUT" | grep -o '"notification_type"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*: *"\([^"]*\)".*/\1/' || true)

    case "$NOTIFICATION_TYPE" in
        permission_prompt)
            WAVEFORM="$WAVEFORM_PERMISSION"
            ;;
        idle_prompt)
            WAVEFORM="$WAVEFORM_IDLE"
            ;;
        elicitation_dialog)
            WAVEFORM="$WAVEFORM_QUESTION"
            ;;
        auth_success)
            WAVEFORM="$WAVEFORM_AUTH"
            ;;
        *)
            # Default for unknown notification types
            WAVEFORM="$WAVEFORM_DEFAULT"
            ;;
    esac
fi

# Trigger haptic feedback if we have a waveform
if [ -n "$WAVEFORM" ]; then
    # Send haptic request (silent, non-blocking, ignore errors)
    curl -s -X POST -d "" "${HAPTIC_API}/${WAVEFORM}" --connect-timeout 2 --max-time 5 >/dev/null 2>&1 || true
fi

exit 0
