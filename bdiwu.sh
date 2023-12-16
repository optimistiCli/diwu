#!/bin/bash

set -e

# Global constants

TEMPLATE_INFIX='template'
ADDUSER_FILE_NAME="addusers.$TEMPLATE_INFIX.sh"
DEFAULT_GUEST_SIDE_GROUP_ID='100'
SEARCH_HOST_SIDE_GROUP=" \
        docker \
        administrators \
        "
SEARCH_ADDUSERS=" \
        scripts/users/ \
        scripts/ \
        ./ \
        "
SEARCH_TEMPLATES=" \
        scripts/guest/ \
        config/ \
        "
# Shuld be even number
MAX_SPLITTER=72

# Functions

function usage {
cat <<EOU >&2
Usage:
  $(basename "$0") [-h] [-s] [-i <image name>] [-g <group name>]
    [-G <users group id> ] [-a <adduser template> | -A] [-t <tag> | -T]
    [-- <extra options passed to 'docker build'>]

Builds specified docker image, creating users from given group.

Options:
  -h Print help and exit
  -s Simmulate, just print out commands
  -i Image name, current dir name used if ommited
  -f Docker file, if ommited looks for:
     '<image name>.dockerfile', 'Dockerfile'
  -g Name of the selected host-side users group, if ommited tries using:
     '$(sed -E "s/^[[:blank:]]*//; s/[[:blank:]]*$//; s/[[:blank:]]+/', '/g" <<<$SEARCH_HOST_SIDE_GROUP)'
  -G Id of the guest-side primary users group, if ommited:
     $DEFAULT_GUEST_SIDE_GROUP_ID
  -a Adduser script template, if ommited looks for '$ADDUSER_FILE_NAME' in:
     '$(sed -E "s/^[[:blank:]]*//; s/[[:blank:]]*$//; s/[[:blank:]]+/', '/g" <<<$SEARCH_ADDUSERS)'
  -A Do not generate adduser script
  -t Tag image something else instead of 'latest'
  -T Build time-tagged image only, do NOT tag it as 'latest'

EOU
}

brag_and_exit () {
        if [ -n "$1" ] ; then
                ERR_MESSAGE="$1"
        else
                ERR_MESSAGE='Something went terribly wrong'
        fi
        echo "Error: $ERR_MESSAGE"$'\n' >&2
        usage
        exit 1
}

moan_and_keep_going () {
        if [ -n "$1" ] ; then
                ERR_MESSAGE="$1"
        else
                ERR_MESSAGE='Something is amiss'
        fi
        echo "Warning: $ERR_MESSAGE"$'\n' >&2
}

function print_eqs {
    printf "%${1}s" '' | tr ' ' '='
}

function detemplate_name {
    sed -E 's/^(.*)\.'"$TEMPLATE_INFIX"'\.(.*)/\1.\2/' <<<"$1"
}

function cook_template_re {
    local VAR
    local RE
    for VAR in $1; do
        RE="${RE}"'s±\$'$VAR'±$'$VAR'±g\; '
    done
    eval echo "$RE"
}

# Start doing stuff

while getopts ":i:f:g:G:a:t:hTsA" OPT ; do
    case $OPT in
        h) # Print help and exit
            usage
            exit 0
            ;;
        i) # Image name
            IMG_NAME="$OPTARG"
            ;;
        f) # Dockerfile
            DOCKERFILE="$OPTARG"
            ;;
        g) # Host-side group
            HOST_SIDE_GROUP="$OPTARG"
            ;;
        G) # Guest-side group id
            GUEST_SIDE_GROUP_ID="$OPTARG"
            ;;
        a) # Adduser template
            ADDUSER_TEMPLATE="$OPTARG"
            ;;
        A) # No adduser
            NO_ADDUSER=1
            ;;
        T) # Don't tag as lates
            NO_EXTRA_TAG=1
            ;;
        t) # Tag test
            EXTRA_TAG="$OPTARG"
            ;;
        s) # Simmulate
            SIMMULATE='echo'
            ;;
    esac
done

shift $(( $OPTIND - 1 ))

if [ -z "$NO_ADDUSER" ]; then
    if [ -z "$ADDUSER_TEMPLATE" ]; then
        for AUSD in $SEARCH_ADDUSERS; do
            T="${AUSD}/${ADDUSER_FILE_NAME}"
            if [ -e "$T" ]; then
                ADDUSER_TEMPLATE="$T"
                break
            fi
        done
    else
        if ! [ -e "$ADDUSER_TEMPLATE" ]; then
            brag_and_exit "No adduser script template: '$ADDUSER_TEMPLATE'"
        fi
    fi

    if [ -z "$ADDUSER_TEMPLATE" ]; then
        moan_and_keep_going "No adduser script template found"
        NO_ADDUSER=1
    fi
fi

if [ -z "$NO_ADDUSER" ]; then
    GUEST_SIDE_GROUP_ID="${GUEST_SIDE_GROUP_ID-$DEFAULT_GUEST_SIDE_GROUP_ID}"

    if [ -z "$HOST_SIDE_GROUP" ]; then
        for DEF_GR in docker administrators; do
            if grep -qE "^${DEF_GR}:" /etc/group; then
                HOST_SIDE_GROUP="$DEF_GR"
                break
            fi
        done
    else
        if ! grep -qE "^${HOST_SIDE_GROUP}:" /etc/group; then
            brag_and_exit "Starnge host-side group: '$HOST_SIDE_GROUP'"
        fi
    fi
    if [ -z "$HOST_SIDE_GROUP" ]; then
        brag_and_exit "No host-side group"
    fi
fi

IMG_NAME="${IMG_NAME-$(basename "$(realpath .)")}"
if ! grep -qE '^[a-zA-Z][a-zA-Z0-9_\-]*$' <<<"$IMG_NAME"; then
    brag_and_exit "Bad image name: '$IMG_NAME"
fi

if [ -z "$DOCKERFILE" ]; then
    for DEF_DF in "${IMG_NAME}.dockerfile" Dockerfile; do
        if [ -e "$DEF_DF" ]; then
            DOCKERFILE="$DEF_DF"
            break
        fi
    done
else
    if ! [ -e "$DOCKERFILE" ]; then
        brag_and_exit "Starnge docker file: '$DOCKERFILE'"
    fi
fi
if [ -z "$DOCKERFILE" ]; then
    brag_and_exit "No docker file"
fi

if [ -n "$EXTRA_TAG" ]; then
    if ! egrep -q '^[a-zA-Z0-9_][a-zA-Z0-9_\.\-]{,127}$' <<<"$EXTRA_TAG"; then
        brag_and_exit "Strange tag: '$EXTRA_TAG'"
    fi
else
    EXTRA_TAG='latest'
fi

# All checks should be over at this point

TIMESTAMP="$(date -u +%Y.%m.%d.%H.%M.%S)"
TIMED_TAG="${IMG_NAME}:${TIMESTAMP}"

TEMP_DIR="$(mktemp -d .diwu_${TIMESTAMP}_XXXXXX)"

ADDUSERS_SCRIPT_NAME="$(detemplate_name "$ADDUSER_FILE_NAME")"

if [ -z "$NO_ADDUSER" ]; then
    ADDUSERS_SCRIPT="${TEMP_DIR}/${ADDUSERS_SCRIPT_NAME}"

    ADDUSERS_LIST="$(cat /etc/group \
        | grep -E "^$HOST_SIDE_GROUP" \
        | cut -d : -f 4 \
        | sed 's/,/\n/g'\
    )"

    TEMPLATE="$(grep -vE -e '^[[:blank:]]*#' -e '^[[:blank:]]*$' "$ADDUSER_TEMPLATE")"

    ADDUSER_VARS='USER_NAME USER_ID USER_GROUP_ID'

    while IFS='' read -r -d $'\n' LINE; do
        IFS=':' read USER_NAME _ USER_ID USER_GROUP_ID _ <<<"$LINE"
        if [ $USER_GROUP_ID -eq $GUEST_SIDE_GROUP_ID ]; then
            if grep -Eq "^$USER_NAME$" <<<"$ADDUSERS_LIST"; then
                {
                    if [ -n "$SEP" ]; then
                        echo ''
                    fi
                    sed "$(cook_template_re "$ADDUSER_VARS")" <<<"${TEMPLATE}"
                }>>"$ADDUSERS_SCRIPT"
                SEP=1
            fi
        fi;
    done</etc/passwd

    ADDUSER_OPT="--build-arg ADDUSERS=${ADDUSERS_SCRIPT}"
fi

### DEBUG
LFTP_NICK=example
LFTP_PORT=123
LFTP_USER=auser
LFTP_SITE=ftp.so.me

EXTRA_VARS_NAMES='LFTP_NICK LFTP_PORT LFTP_USER LFTP_SITE'

EXTRA_RE_COOKED="$(cook_template_re "$EXTRA_VARS_NAMES")"
### DEBUG

while IFS='' read -r -d $'\n' EXTRA_TEMPLATE_FILE; do
    EXTRA_COOKED_FILE_NAME="$(detemplate_name "$(basename $EXTRA_TEMPLATE_FILE)")"
    if [ "$EXTRA_COOKED_FILE_NAME" = "$ADDUSERS_SCRIPT_NAME" ]; then
        moan_and_keep_going "Prevented cooking addusers script from alternative template"
        continue
    fi
    EXTRA_COOKED_FILE="${TEMP_DIR}/${EXTRA_COOKED_FILE_NAME}"
    if [ -e "$EXTRA_COOKED_FILE" ]; then
        moan_and_keep_going "Prevented overwriting cooked file: '$EXTRA_COOKED_FILE_NAME'"
        continue
    fi
    sed "$EXTRA_RE_COOKED" <"$EXTRA_TEMPLATE_FILE" >"$EXTRA_COOKED_FILE"
done <<<"$( \
    find $SEARCH_TEMPLATES \
            -not \( -path '*/.*' -or -path '*/@*' \) \
            -type f \
            -name "*.$TEMPLATE_INFIX.*" \
            )"

if [ -n "$SIMMULATE" ]; then
    while IFS='' read -r -d $'\n' N; do
        P="${TEMP_DIR}/${N}"
        if [ -d  "$P" ]; then
            continue
        fi
        NL=$(( $(wc -c <<<"$N") - 1 ))
        QR=$(( ( ( $MAX_SPLITTER - 3 ) - $NL ) / 2 ))
        if [ $(( $NL % 2 )) -eq 0 ]; then
            # Even
            QL=$QR
        else
            # Odd
            QL=$(( $QR - 1 ))
        fi
        if [ $QL -lt 3 ]; then
            QL=3
            QR=3
        fi
        UP_SEP="$(print_eqs $QL) $N $(print_eqs $QR)"
        echo ">$UP_SEP<";
        cat "$P"
        echo ">$(print_eqs $(( $(wc -c <<<"$UP_SEP") - 1 )) )<"
    done <<<"$(ls -1 $TEMP_DIR)"
fi

$SIMMULATE docker build \
    -f "$DOCKERFILE" \
    -t "$TIMED_TAG" \
    $ADDUSER_OPT "$@" .

rm -rfv "$TEMP_DIR"

if [ -z "$NO_EXTRA_TAG" ]; then
    $SIMMULATE docker tag "$TIMED_TAG" "${IMG_NAME}:${EXTRA_TAG}"
fi
