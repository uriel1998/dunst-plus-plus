#!/usr/bin/env bash

################################################################################
#  dunst_plusplus
#
#  to take dunst (or any) notifications, process them, and re-issue to dunst.
#  runner.sh -> what calls the submodules
#
#  by Steven Saus
###############################################################################

set -euo pipefail

# Resolve the real script path once so preview and helper subprocesses can
# re-enter this same file no matter where the user launched it from.


LOUD=0
SCRIPT_DIR="$( cd "$(dirname $(readlink -f "${0}"))" ; pwd -P )"
SCRIPT_PATH="$(readlink -f "${0}")"
SCRIPT_NAME="$(basename "${0}")"
mkdir -p "${SCRIPT_DIR}/cache"
notification_appname=""
notification_summary=""
notification_body=""
notification_icon=""
notification_time=""
MESSAGE_CACHE_FILE="${SCRIPT_DIR}/cache/messages"


# Built-in CLI help for normal users. Internal preview helper arguments are
# intentionally omitted because they are implementation details.
show_help() {
  cat <<EOF
Usage:
  ${SCRIPT_NAME} [list-name]
  ${SCRIPT_NAME} --help

enrich those notifications

EOF
}


function die() {
    printf "%s\n" "$@" >&2
    exit 1
}


function require_command() {
    command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}


function loud() {
##############################################################################
# loud outputs on stderr
##############################################################################
    if [ $LOUD -eq 1 ];then
        echo "$@" 1>&2
    fi
}

function chatapps(){
    #these are global, but wtf.
    local n_appname="${1}" # app
    local n_summary="${2}" # name
    local n_body="${3}"  # message
    local n_icon="${4}"  # the icon
    local n_time=$(date +%Y%m%d%H%M%S) #our date here

# do we have a recent message which includes the same body?
# if not, do we have a non-generic icon?
# substitute icon, name, appname (and such)
# re-present to dunst

}




########################################################################################
########################################################################
# Get command-line parameters
########################################################################
while [ $# -gt 0 ]; do
    option="$1"
    case $option in
        --loud|-l)
            LOUD=1
            ;;
        --help|-h)
            display_help
            exit 0
            ;;
        *)
            # if it is not help or loud, it's the data from dunst
            notification_appname="${1}"
            notification_summary="${2}"
            notification_body="${3}"
            notification_icon="${4}"
            notification_time=$(date +%Y%m%d%H%M%S)
            ;;
    esac
    shift
done

########################################################################
# Main
########################################################################

# require_commands if needed?
if [ "${1}" == "--loud" ];then
    LOUD=1
    shift
fi


case "$notification_appname" in
    gomuks|cinny|beeper|equibop)
        process_chat "${1}" "${2}" "${3}" "${4}" "${5}"
        ;;
    *) # at present, this shouldn't be hit at all;
        ;;
esac
