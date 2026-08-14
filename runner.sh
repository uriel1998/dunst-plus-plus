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
CONFIGSTORE="${SCRIPT_DIR}/configstore"
HISTORY_TIME=30 #this is in seconds, not lines or entries.

function loud() {
##############################################################################
# loud outputs on stderr
##############################################################################
    if [ $LOUD -eq 1 ];then
        echo "$@" 1>&2
    fi
}

die() {
    printf '%s\n' "$*" >&2
    exit 1
}

# Built-in CLI help for normal users. Internal preview helper arguments are
# intentionally omitted because they are implementation details.
show_help() {
  cat <<'EOF'
Usage:
  runner.sh [appname] [summary] [body] [icon]
  runner.sh --help

enrich those notifications
this is meant to be called from dunst.
--help|-h  this.
--loud     give extra feedback
appname
summary     display name, may include tags from chat clients
body        message body
icon        original icon path or name

EOF
}


function require_command() {
    command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

copy_icon_as_png() {
    local source_path="${1:?copy_icon_as_png: source path required}"
    local dest_path="${2:?copy_icon_as_png: destination path required}"

    if command -v magick >/dev/null 2>&1; then
        magick "${source_path}" "${dest_path}"
        return 0
    fi

    if command -v convert >/dev/null 2>&1; then
        convert "${source_path}" "${dest_path}"
        return 0
    fi

    die "Missing required command: magick or convert"
}



function clean_phone_number() {
    # parse for standardization
    # derived from https://www.kodikra.com/2026/04/phone-number-in-bash-complete-solution.html
        local input="${1:-}"
        local result
        local correct_pattern='^1?[2-9][0-9]{2}[2-9][0-9]{6}$'

        # Require exactly one non-empty argument.
        if [[ $# -ne 1 || -z "$input" ]]; then
            printf 'clean_phone_number: requires one phone number\n' >&2
            return 1
        fi

        # Remove everything except digits.
        result="${input//[^0-9]/}"

        # Validate as NANP: optional leading 1, then NXX-NXX-XXXX.
        if [[ ! "$result" =~ $correct_pattern ]]; then
            printf 'clean_phone_number: invalid NANP number: %s\n' "$input" >&2
            return 1
        fi

        # Always return the final 10 digits, stripping country code 1 if present.
        printf '%s\n' "${result: -10}"
    }


function phone_needs_standardization() {
        local input="${1:-}"
        local cleaned

        [[ $# -eq 1 && -n "$input" ]] || return 1

        # Must first be a valid NANP phone number.
        cleaned="$(clean_phone_number "$input" 2>/dev/null)" || return 1

        # Return success only if the original differs from canonical form.
        [[ "$input" != "$cleaned" ]]
    }

function is_phone_number() {
        clean_phone_number "$1" >/dev/null 2>&1
    }

function pretty_phone_number() {
        local cleaned="${1:-}"

        [[ $# -eq 1 && "${cleaned}" =~ ^[0-9]{10}$ ]] || return 1

        printf '(%s) %s-%s\n' "${cleaned:0:3}" "${cleaned:3:3}" "${cleaned:6:4}"
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
    local compare_field1=""
    local compare_item=""
    local display_field1=""
    local default_display_field1=""

    #standardize phone numbers
    # does the identifier look like a phone number?
        # if so, pass it to standardize_phone
        # and then make that the identifier
        if is_phone_number "${identifier}"; then               # valid NANP number?
            if phone_needs_standardization "${identifier}"; then   # valid NANP AND not already 10 digits?
                identifier=$(clean_phone_number "${identifier}")   # return canonical 10-digit version
            fi
        fi
        default_display_field1="${identifier}"
        if [[ "${identifier}" =~ ^[0-9]{10}$ ]]; then
            default_display_field1="$(pretty_phone_number "${identifier}")"
        fi



    if [[ -z "${CONFIGSTORE:-}" || ! -f "${CONFIGSTORE}" ]]; then
        sha="$(generate_avatar "${identifier}")" || return 1
        printf '%s:%s\n' "${display_field1}" "${sha}"
        return 0
    fi

    while IFS= read -r line || [[ -n "${line}" ]]; do
        # Ignore blank lines and comments.
        [[ -z "${line}" || "${line}" == \#* ]] && continue

        IFS=: read -r field1 field2 field3 <<< "${line}"
        compare_field1="${field1}"
        display_field1="${field1}"

        if is_phone_number "${field1}"; then
            compare_field1="$(clean_phone_number "${field1}")"
            display_field1="$(pretty_phone_number "${compare_field1}")"
        fi

        # Does identifier match field 1?
        if [[ "${compare_field1}" != "${identifier}" ]]; then
            # If not, check each comma-separated alias in field 3.
            local matched=false

            IFS=',' read -ra aliases <<< "${field3}"
            for item in "${aliases[@]}"; do
                # Trim leading/trailing whitespace.
                item="${item#"${item%%[![:space:]]*}"}"
                item="${item%"${item##*[![:space:]]}"}"
                compare_item="${item}"

                if is_phone_number "${item}"; then
                    compare_item="$(clean_phone_number "${item}")"
                fi

                if [[ "${compare_item}" == "${identifier}" ]]; then
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
            # Field 2 is a bootstrap image path. Cache it under the identifier SHA.
            sha="$(printf '%s\n' "${identifier}" | /usr/bin/shasum | awk '{print $1}')" || return 1
            mkdir -p "${ICON_CACHE}"
            copy_icon_as_png "${field2}" "${ICON_CACHE}/${sha}.png" || return 1

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

            printf '%s:%s\n' "${display_field1}" "${sha}"
            return 0
        fi

        # Field 2 wasn't a filename, so assume it is already the SHA.
        printf '%s:%s\n' "${display_field1}" "${field2}"
        return 0
    done < "${CONFIGSTORE}"

    #
    # No existing identifier was found.
    # Generate a deterministic SHA from the identifier itself.
    #
    sha="$(generate_avatar "${identifier}")" || return 1
    printf '%s:%s\n' "${default_display_field1}" "${sha}"

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
    local nowtime=""

    mkdir -p "$(dirname "${MESSAGE_CACHE_FILE}")"
    touch "${MESSAGE_CACHE_FILE}"

    nowtime=$(date +%s)
    teststring=$(printf '%s' "${msg_to_test}" | /usr/bin/shasum | awk '{print $1}')
    testtime="$(awk -F ':' -v hash="${teststring}" '$2 == hash { ts=$1 } END { print ts }' "${MESSAGE_CACHE_FILE}")"

    if [[ -n "${testtime}" ]] && (( nowtime - testtime < time_diff )); then
        loud "[warn] found duplicate"
        return 99
    fi

    printf "%s:%s\n" "${nowtime}" "${teststring}" >> "${MESSAGE_CACHE_FILE}"
    return 0
}

function trim_history () {
    local tempfile=""

    mkdir -p "$(dirname "${MESSAGE_CACHE_FILE}")"
    touch "${MESSAGE_CACHE_FILE}"
    tempfile=$(mktemp)
    cp "${MESSAGE_CACHE_FILE}" "${tempfile}"
    tail -n 300 "${tempfile}" > "${MESSAGE_CACHE_FILE}"
    rm -f "${tempfile}"
}


function chat_apps(){
    #these are global, but wth.
    local n_appname="${1}" # app
    local n_summary="${2}" # name  #may also include tags from discord
    local n_body="${3}"  # message
    local n_icon="${4}"  # the icon
    local result=""
    local nl_icon=""
    local nl_name=""
    # this is where you could further customize treatment per app, etc for the action buttons for quick replies and all that.

    #is it from someone we already know?
    # this also generates missing avatars
    # this also converts icons to our shasum too
    result=$(search_for_identifier "${n_summary}")
    if [ -n "${result}" ];then
        IFS=: read -r nl_name nl_icon <<< "${result}"
        nl_icon="${ICON_CACHE}/${nl_icon}.png"

        if [ -z "${nl_name}" ]; then
            nl_name="${n_summary}"
        fi
    fi
    # Appending id after standarization to body, that way it's more robust duplicate detection without false hits
    if chat_search_for_prior "${HISTORY_TIME}" "${nl_name}${n_body}"; then
        #it is not a duplicate
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

    local seed=""
    local api_style=""
    local avatar_dir="${ICON_CACHE}"

    if [ "$#" -eq 0 ];then
           #no input given, get random
           seed=$(tr -dc 'a-zA-Z0-9' < /dev/urandom | fold -w 32 | head -n 1 | /usr/bin/shasum | awk '{print $1}')
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
        printf '%s\n' "${seed}"
        return 0
    fi

    return 1
}

########################################################################
# Main
########################################################################
# positional initial commands
# require_commands if needed?

if [ "${1-}" == "--help" ] || [ "${1-}" == "-h" ];then
    show_help
    exit 0
fi

if [ "${1-}" == "--loud" ];then
    LOUD=1
    shift
fi

if [ "$#" -lt 4 ]; then
    die "Usage: ${SCRIPT_NAME} [--loud] appname summary body icon"
fi

require_command notify-send
require_command /usr/bin/shasum
require_command wget

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
