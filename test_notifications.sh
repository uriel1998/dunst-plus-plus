#!/usr/bin/env bash

set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
DELAY_SECONDS="${DELAY_SECONDS:-1}"
RUN_ID="$(date +%s)"
DRY_RUN=0

show_help() {
    cat <<'EOF'
Usage
  ./test_notifications.sh [--dry-run] [--help]

Description
  Emit a set of notify-send messages that exercise dunst_plusplus channel
  priorities, keyword priorities, and exclusions.

Options
  --dry-run  Print the notify-send commands without sending them.
  --help     Show this help text and exit.

Environment
  DELAY_SECONDS   Seconds to sleep between test notifications. Default: 1
EOF
}

send_case() {
    local label="${1:?send_case: label required}"
    local appname="${2:?send_case: appname required}"
    local summary="${3:?send_case: summary required}"
    local body="${4:?send_case: body required}"
    local icon="dialog-information"

    printf '[test] %s\n' "${label}"
    printf '       app=%s\n' "${appname}"
    printf '       summary=%s\n' "${summary}"
    printf '       body=%s\n' "${body}"

    if [ "${DRY_RUN}" -eq 1 ]; then
        printf '       cmd=notify-send -a %q -i %q %q %q\n' \
            "${appname}" "${icon}" "${summary}" "${body}"
    else
        notify-send -a "${appname}" -i "${icon}" "${summary}" "${body}"
    fi

    sleep "${DELAY_SECONDS}"
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --dry-run)
            DRY_RUN=1
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
        *)
            printf 'Unknown option: %s\n' "$1" >&2
            show_help >&2
            exit 1
            ;;
    esac
    shift
done

send_case \
    "channel-high whitelist" \
    "gomuks" \
    "Sample Contact (#build-alerts)" \
    "Channel whitelist test ${RUN_ID}."

send_case \
    "channel-med yellowlist" \
    "gomuks" \
    "Sample Contact (#general-chat)" \
    "Channel yellowlist test ${RUN_ID}."

send_case \
    "channel-low redlist" \
    "gomuks" \
    "Sample Contact (#offtopic)" \
    "Channel redlist test ${RUN_ID}."

send_case \
    "keyword-high override" \
    "gomuks" \
    "Sample Contact (#offtopic)" \
    "Please escalate this urgent account keyword-high test ${RUN_ID}."

send_case \
    "keyword-med override" \
    "gomuks" \
    "Sample Contact (#offtopic)" \
    "This is a review requested keyword-med test ${RUN_ID}."

send_case \
    "keyword-low only" \
    "gomuks" \
    "Sample Contact (#unknown-channel)" \
    "This is a background task keyword-low test ${RUN_ID}."

send_case \
    "exclude gomuks" \
    "gomuks" \
    "Sample Contact (#general-chat)" \
    "Bridge bot invited ${RUN_ID}"

send_case \
    "exclude beeper" \
    "Beeper" \
    "Sample Contact" \
    "Plugin error ${RUN_ID}"

send_case \
    "non-gomuks baseline" \
    "Beeper" \
    "Sample Contact" \
    "Regular non-gomuks routing test ${RUN_ID}."
