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
ICON_CACHE="${SCRIPT_DIR}/cache/icons"
CONFIGSTORE="${SCRIPT_DIR}configstore"
HISTORY_TIME=300 #this is in seconds, not lines or entries.

function loud() {
##############################################################################
# loud outputs on stderr
##############################################################################
    if [ $LOUD -eq 1 ];then
        echo "$@" 1>&2
    fi
}

# Built-in CLI help for normal users. Internal preview helper arguments are
# intentionally omitted because they are implementation details.
show_help() {
  cat <<EOF
Usage:
  ${SCRIPT_NAME} [list-name]
  ${SCRIPT_NAME} --help

enrich those notifications
this is meant to be called from dunst.
--help|-h  this.
--loud     give extra feedback
appname
summary="${2}" # name  #may also include tags from discord
body="${3}"  # message
icon="${4}"  # the icon

EOF
}


function require_command() {
    command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

function search_for_identifier(){
     # take in identifier
    # search in ${CONFIGSTORE} (already defined)
    # look in first and third field for any item between commas that matches
        # found match? check second field
        # get EITHER filename or shasum.
        # if filename, call generate_avatar
            # it will return a shasum
            # replace the file path line in the configstore with the shasum version
    # if neither, create an icon with a shasum of the ID passed in
    # return shasum


    local identifier="${1:?search_for_identifier: identifier required}"
    local line field1 field2 field3 item
    local sha new_line

    if [[ -z "${CONFIGSTORE:-}" || ! -f "${CONFIGSTORE}" ]]; then
        printf 'search_for_identifier: CONFIGSTORE does not exist: %s\n' \
            "${CONFIGSTORE:-<unset>}" >&2
        return 1
    fi

    while IFS= read -r line || [[ -n "${line}" ]]; do
        # Ignore blank lines and comments.
        [[ -z "${line}" || "${line}" == \#* ]] && continue

        IFS=: read -r field1 field2 field3 <<< "${line}"

        # Does identifier match field 1?
        if [[ "${field1}" != "${identifier}" ]]; then
            # If not, check each comma-separated alias in field 3.
            local matched=false

            IFS=',' read -ra aliases <<< "${field3}"
            for item in "${aliases[@]}"; do
                # Trim leading/trailing whitespace.
                item="${item#"${item%%[![:space:]]*}"}"
                item="${item%"${item##*[![:space:]]}"}"

                if [[ "${item}" == "${identifier}" ]]; then
                    matched=true
                    break
                fi
            done

            "${matched}" || continue
        fi

        #
        # We found the identifier.
        #

        if [[ -f "${field2}" ]]; then
            # Field 2 is a filename. Generate the avatar and obtain its SHA.
            sha="$(generate_avatar "${field2}")" || return 1

            # Replace only this exact config line, preserving fields 1 and 3.
            new_line="${field1}:${sha}:${field3}"

            awk -v old="${line}" -v new="${new_line}" '
                $0 == old && !done {
                    print new
                    done=1
                    next
                }
                { print }
            ' "${CONFIGSTORE}" > "${CONFIGSTORE}.tmp" || {
                rm -f "${CONFIGSTORE}.tmp"
                return 1
            }

            mv "${CONFIGSTORE}.tmp" "${CONFIGSTORE}" || return 1

            printf '%s:%s\n' "${field1}" "${sha}"
            return 0
        fi

        # Field 2 wasn't a filename, so assume it is already the SHA.
        printf '%s:%s\n' "${field1}" "${field2}"
        return 0
    done < "${CONFIGSTORE}"

    #
    # No existing identifier was found.
    # Generate a deterministic SHA from the identifier itself.
    #
    sha="$(generate_avatar "${identifier}")"
    printf '%s\n' "${sha}"

}



function chat_search_for_prior(){
    #take in message and time.
    #check cache file for message within TIME period of TIME
    #return 0 (good) or 1 (error) or 99 (prior found)
    # shasum here allows us to compare, but not have to care about spaces, etc.
    local time_diff="${1}"
    local msg_to_test="${2}"
    local teststring=""
    local testtime=""
    nowtime=$(date +%s)
    if [ (( $nowtime - $testtime )) -lt $time_diff ];then
    teststring=$(printf '%s' "${msg_to_test}" | shasum | awk '{print $1}')
    if rg -i "${teststring}" "${MESSAGE_CACHE_FILE}" then
        # if it's already in cache, check time.
        testtime=$(awk -F ':' '{ print $1 }')
            loud "[warn] found duplicate"
            return 99
        fi
        # other one is stale and old, rewrite.
        printf "%s:%s\n" "${nowtime}" "${msg_to_test}" >> "${MESSAGE_CACHE_FILE}"
    else
        #brand new day, write.
        printf "%s:%s\n" "${nowtime}" "${msg_to_test}" >> "${MESSAGE_CACHE_FILE}"
    fi
    return 0
}

function trim_history () {
    local tempfile=""

    tempfile=$(mktemp)
    cp "${MESSAGE_CACHE_FILE}" "${tempfile}"
    tail -n 300 "${tempfile}" > "${MESSAGE_CACHE_FILE}"
    rm "${tmpfile}"
}


function chat_apps(){
    #these are global, but wth.
    local n_appname="${1}" # app
    local n_summary="${2}" # name  #may also include tags from discord
    local n_body="${3}"  # message
    local n_icon="${4}"  # the icon
    local n_time=$(date +%s) #time of processing
    local result=""
    local n_shasum=""
    local nl_icon=""
    local nl_name=""
    # this is where you could further customize treatment per app, etc for the action buttons for quick replies and all that.

    # if not, do we have a non-generic icon?
    # substitute icon, name, appname (and such)

    result=$(chat_search_for_prior "${n_body}" "$HISTORY_TIME"; echo "$?")

    if [ $result -eq 0 ];then
        #it is not a duplicate
        #is it from someone we already know?
        # this also generates missing avatars
        # this also converts icons to our shasum too
        result=$(search_for_identifier "${n_summary}")
        if [ "${result}" != "" ];then
            IFS=: read -r nl_name nl_icon <<< "${result}"
            nl_icon="${ICON_CACHE}/${nl_icon}.png"

            # re-present to dunst with a different app name so it hits a different rule.
            notify-send -a visible-chat -i "${nl_icon}" "${nl_name}" "${n_body}"
    else
        loud "[warn] it was a duplicate" #it *is* a duplicate
    fi



}








function generate_avatar(){
    # pass in the hash of whatever the identifier is.

    # I think just using the dicebear wrapper I made makes sense here.
    # I'm not trying to standardize to VCards, or even search them.
    # But that way if you pass the same information (or encode a username) it works

    if [ "$#" -eq 0 ];then
	       #no input given, get random
           seed=$(tr -dc 'a-zA-Z0-9' < /dev/urandom | fold -w 32 | head | /usr/bin/shasum | awk '{print $1}' )
    else
	       seed=$(printf "%s\n" "${@}" | /usr/bin/shasum | awk '{print $1}')
    fi

    mkdir -p "${avatar_dir}"

    # If you already did it once, don't do it again

    if [ ! -f "${avatar_dir}/${seed}.png" ];then
        # Randomize the online DiceBear style for new cached avatars.
        if [ $((RANDOM % 2)) -eq 0 ]; then
           api_style="clay"
        else
            api_style="critters"
        fi

		if ! wget -q "https://api.dicebear.com/10.x/${api_style}/png?animationVariant=&backgroundColor=5e5c64,813d9c,613583,1c71d8,1a5fb4,26a269&backgroundColorAngle=-67&backgroundColorFillStops=2&size=512&seed=${seed}" -O "${avatar_dir}/${seed}.png"; then
            rm -f "${avatar_dir}/${seed}.png"
        fi

    	# Okay, if that didn't work, then the local install with the robots one

    	if [ ! -f "${avatar_dir}/${seed}.png" ];then
    		if command -v dicebear >/dev/null 2>&1; then
    			dicebear bottts "${avatar_dir}" --animationVariant --backgroundColor '5e5c64' '813d9c' '613583' '1c71d8' '1a5fb4' '26a269' --format png --seed "${seed}"
    			# note the name needs to match
    			mv "${avatar_dir}/bottts-0.png" "${avatar_dir}/${seed}.png"
    		fi
    	fi
    fi

    if [ -f "${avatar_dir}/${seed}.png" ];then
        # now if it was a filename, replace it inline with sed
    fi

}

resend_payload (){
    # take in all the needed parts of the message,
    # resend with different header so it goes forward as we want.

}


########################################################################
# Main
########################################################################
# positional initial commands
# require_commands if needed?

if [ "${1}" == "--help" ] || [ "${1}" == "-h" ];then
    show_help
    exit 0
fi

if [ "${1}" == "--loud" ];then
    LOUD=1
    shift
fi

# $1 is the appname from dunst before dunst called this.
case "$1" in
    gomuks|cinny|beeper|equibop)
        chat_apps "${1}" "${2}" "${3}" "${4}"
        ;;
    # could be from deliveries, or ringing or whatever.
    # point being from here you can script it however
    *) # at present, this shouldn't be hit at all;
        ;;
esac

trim_history
