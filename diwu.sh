#!/bin/bash 

# TODO: Option to disable vars warning
# TODO: Fail (or warn?) if no users
# TODO: Add addgroup.template.sh
# TODO: Add option for extra extra templates / templates dirs

set -e

# Global constants

C_TEMPLATE_INFIX='template'
C_ADDUSER_FILE_NAME="addusers.$C_TEMPLATE_INFIX.sh"
C_SEARCH_HOST_SIDE_GROUP='
    docker
    administrators
'
C_SEARCH_ADDUSERS='
    scripts/users/
    scripts/
    ./
'
C_SEARCH_TEMPLATES='
    scripts/guest/
    config/
'
# You do **not** want to edit this one!
C_ADDUSER_VARS='
    USER_NAME 
    USER_ID 
    USER_GROUP_ID
'
C_VARS_FILE_SUFFIX='vars.ini'
# Shuld be an even number
C_MAX_SPLITTER=72

# Functions

function usage {
cat <<EOU >&2
Usage:
  $(basename "$0") [-h] [-s] [-i <image name>] [-g <group name>]
    [-G <users group id> ] [-a <adduser template> | -A] [-t <tag> | -T]
    [-e <vars file>] [-L] [-- <extra options passed to 'docker build'>]

Builds specified docker image, creating users from given group.

Options:
  -h Print help and exit
  -s Simulate, just print out commands
  -i Image name, current dir name used if omitted
  -f Docker file, if omitted looks for:
     '<image name>.dockerfile', 'Dockerfile'
  -g Name of the selected host-side users group, if omitted tries using:
     $(present_list "$C_SEARCH_HOST_SIDE_GROUP")
  -G Id of the guest-side primary users group, if omitted host-side GID is used
  -a Adduser script template, if omitted looks for '$C_ADDUSER_FILE_NAME' in:
     $(present_list "$C_SEARCH_ADDUSERS")
  -A Do not generate adduser script
  -t Tag image something else instead of 'latest'
  -T Build time-tagged image only, do NOT tag it as 'latest'
  -e File defining variables for extra templates, if omitted looks for:
     '<image name>.$C_VARS_FILE_SUFFIX'
  -L List images with timed tag only and exit

EOU
}

brag_and_exit () {
        local ERR_MESSAGE
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
        local ERR_MESSAGE
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
    sed -E 's/^(.*)\.'"$C_TEMPLATE_INFIX"'\.(.*)/\1.\2/' <<<"$1"
}

C_TEMPLATE_PRE_RE='^[[:blank:]]*([a-z_A-Z][[:alnum:]_]*)[[:blank:]]*=[[:blank:]]*'
function cook_template_re {
    while IFS='' read -r -d $'\n' VAR_EQ; do
        echo -n "s%{{$(cut -d '=' -f 1 <<<"$VAR_EQ")}}%$(cut -d '=' -f 2- <<<"$VAR_EQ" | sed 's/%/\\%/g')%g; "
    done <<<"$( \
        egrep "${C_TEMPLATE_PRE_RE}[^[:blank:]]" \
        | sed -E "s/[[:blank:]]*$//; s/${C_TEMPLATE_PRE_RE}(.*)/\1=\2/" \
    )" \
    | sed -E 's/;[[:blank:]]*$//'
}

function present_list {
    echo -n $1 | sed -E "s/^/'/; s/$/'/; s/[[:blank:]]{1,}/', '/g"
}

function list_anonyms {
    local TIMED_TAG_RE=':[0-9]{4}\.[0-9]{2}\.[0-9]{2}\.[0-9]{2}\.[0-9]{2}\.[0-9]{2}:'
    local ALL_IMAGES="$( \
        docker image ls \
            | egrep "^${G_IMG_NAME}[[:blank:]]" \
            | sed -E 's/[[:blank:]]{1,}/:/; s/[[:blank:]]{1,}/:/; s/[[:blank:]].*//' \
    )"
    while IFS='' read -r -d $'\n' LINE; do
        local ID="$(cut -d ':' -f 3 <<<"$LINE")"
        if ! egrep ":${ID}$" <<<"$ALL_IMAGES" \
            | egrep -qv "$TIMED_TAG_RE"
        then
            cut -d ':' -f 1-2 <<<"$LINE"
        fi
    done <<<"$(egrep "$TIMED_TAG_RE" <<<"$ALL_IMAGES")" | sort -u
}

function setup_adduser_template_file {
    if [ -z "$G_ADDUSER_TEMPLATE_FILE" ]; then
        for DIR in $C_SEARCH_ADDUSERS; do
            local CANDIDATE="${DIR}/${C_ADDUSER_FILE_NAME}"
            if [ -e "$CANDIDATE" ]; then
                G_ADDUSER_TEMPLATE_FILE="$CANDIDATE"
                break
            fi
        done
    else
        if ! [ -e "$G_ADDUSER_TEMPLATE_FILE" ]; then
            brag_and_exit "No adduser script template: '$G_ADDUSER_TEMPLATE_FILE'"
        fi
    fi

    if [ -z "$G_ADDUSER_TEMPLATE_FILE" ]; then
        moan_and_keep_going "No adduser script template found"
        G_NO_ADDUSER=1
    fi
}

function get_group_id {
    egrep "^${1}:" /etc/group \
        | cut -d : -f 3
}

function setup_host_group {
    if [ -z "$G_HOST_SIDE_GROUP" ]; then
        for HOST_SIDE_GROUP in $C_SEARCH_HOST_SIDE_GROUP; do
            if egrep -q "^${HOST_SIDE_GROUP}:" /etc/group; then
                G_HOST_SIDE_GROUP="$HOST_SIDE_GROUP"
                break
            fi
        done
    else
        if ! egrep -q "^${G_HOST_SIDE_GROUP}:" /etc/group; then
            brag_and_exit "Starnge host-side group: '$G_HOST_SIDE_GROUP'"
        fi
    fi
    if [ -z "$G_HOST_SIDE_GROUP" ]; then
        brag_and_exit "No host-side group"
    fi
    G_HOST_SIDE_GROUP_ID=$(get_group_id "$G_HOST_SIDE_GROUP")
}

function setup_guest_group {
    G_GUEST_SIDE_GROUP_ID="${G_GUEST_SIDE_GROUP_ID-$G_HOST_SIDE_GROUP_ID}"
}

function setup_users {
    while [ -n "$1" ] && [ -z "$G_NO_ADDUSER" ]; do
        "$1"
        shift
    done
}

# Start doing stuff

while getopts ":i:f:g:G:a:t:e:hTsAL" OPT ; do
    case $OPT in
        h) # Print help and exit
            usage
            exit 0
            ;;
        i) # Image name
            G_IMG_NAME="${OPTARG%.dockerfile}"
            ;;
        f) # Dockerfile
            G_DOCKERFILE="$OPTARG"
            ;;
        g) # Host-side group
            G_HOST_SIDE_GROUP="$OPTARG"
            ;;
        G) # Guest-side group id
            G_GUEST_SIDE_GROUP_ID="$OPTARG"
            ;;
        a) # Adduser template
            G_ADDUSER_TEMPLATE_FILE="$OPTARG"
            ;;
        A) # No adduser
            G_NO_ADDUSER=1
            ;;
        T) # Don't tag as lates
            G_NO_EXTRA_TAG=1
            ;;
        t) # Tag test
            G_EXTRA_TAG="$OPTARG"
            ;;
        e) # Vars file
            G_VARS_FILE="$OPTARG"
            ;;
        s) # Simmulate
            G_SIMMULATE='echo'
            ;;
        L) # List anonymous timed tags
            G_LIST_ANONYMS_AND_EXIT=1
            ;;
    esac
done

shift $(( $OPTIND - 1 ))

G_IMG_NAME="${G_IMG_NAME-$(basename "$(realpath .)")}"
if ! egrep -q '^[a-zA-Z][a-zA-Z0-9_\-]*$' <<<"$G_IMG_NAME"; then
    brag_and_exit "Bad image name: '$G_IMG_NAME'"
fi

if [ -n "$G_LIST_ANONYMS_AND_EXIT" ]; then
    list_anonyms
    exit 0
fi

setup_users \
    setup_adduser_template_file \
    setup_host_group \
    setup_guest_group

if [ -z "$G_DOCKERFILE" ]; then
    for DEF_DF in "${G_IMG_NAME}.dockerfile" Dockerfile; do
        if [ -e "$DEF_DF" ]; then
            G_DOCKERFILE="$DEF_DF"
            break
        fi
    done
else
    if ! [ -e "$G_DOCKERFILE" ]; then
        brag_and_exit "Starnge docker file: '$G_DOCKERFILE'"
    fi
fi
if [ -z "$G_DOCKERFILE" ]; then
    brag_and_exit "No docker file"
fi

if [ -n "$G_EXTRA_TAG" ]; then
    if ! egrep -q '^[a-zA-Z0-9_][a-zA-Z0-9_\.\-]{,127}$' <<<"$G_EXTRA_TAG"; then
        brag_and_exit "Strange tag: '$G_EXTRA_TAG'"
    fi
else
    G_EXTRA_TAG='latest'
fi

if [ -n "$G_VARS_FILE" ]; then
    if ! [ -e "$G_VARS_FILE" ]; then
        brag_and_exit "Strange variables file: '$G_VARS_FILE'"
    fi
else
    G_VARS_FILE="${G_IMG_NAME}.$C_VARS_FILE_SUFFIX"
    if ! [ -e "$G_VARS_FILE" ]; then
        moan_and_keep_going "No variables file found, extra templates will not be processed"
        NO_EXTRA_TEMPLATES=1
    fi
fi

# All checks should be over at this point

TIMESTAMP="$(date -u +%Y.%m.%d.%H.%M.%S)"
TIMED_TAG="${G_IMG_NAME}:${TIMESTAMP}"

TEMP_DIR="$(mktemp -d .diwu_${TIMESTAMP}_XXXXXX)"

ADDUSERS_SCRIPT_NAME="$(detemplate_name "$C_ADDUSER_FILE_NAME")"

if [ -z "$G_NO_ADDUSER" ]; then
    ADDUSERS_SCRIPT="${TEMP_DIR}/${ADDUSERS_SCRIPT_NAME}"

    # TODO: Add main-group users
    ADDUSERS_LIST="$( \
        egrep \
            "^${G_HOST_SIDE_GROUP}:" \
            /etc/group \
            | cut -d : -f 4 \
            | sed 's/,/\n/g'\
    )"

    ADDUSER_TEMPLATE="$( \
        egrep -v \
            '^[[:blank:]]*(#.*)?$' \
            "$G_ADDUSER_TEMPLATE_FILE" \
    )"

    ADDUSER_RE_RAW="$( \
        sed -E \
            's/([^[:blank:]]{1,})/\1 = $\1/' \
            <<<"$C_ADDUSER_VARS" \
            | cook_template_re \
    )"

    while IFS='' read -r -d $'\n' LINE; do
        IFS=':' read $( \
            echo $C_ADDUSER_VARS \
            | sed 's/[[:blank:]]/ _ /; s/$/ _/' \
        ) <<<"$LINE"
        if [ $USER_ID -eq 0 ]; then
            continue
        fi
        # Overriding GID with source host-side group's
        USER_GROUP_ID="$G_GUEST_SIDE_GROUP_ID"
        if egrep -q "^$USER_NAME$" <<<"$ADDUSERS_LIST"; then
            ADDUSER_BUFFER="${ADDUSER_BUFFER+${ADDUSER_BUFFER}$'\n\n'}"
            ADDUSER_BUFFER="${ADDUSER_BUFFER}$( \
                sed \
                    "$(eval "echo \"$ADDUSER_RE_RAW\"")" \
                    <<<"$ADDUSER_TEMPLATE" \
            )"
        fi
    done </etc/passwd
    echo "$ADDUSER_BUFFER" > "$ADDUSERS_SCRIPT"

    ADDUSER_OPT="--build-arg ADDUSERS=${ADDUSERS_SCRIPT}"
fi

if [ -z "$NO_EXTRA_TEMPLATES" ]; then
    EXTRA_RE_COOKED="$(cook_template_re <"$G_VARS_FILE")"

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
        find $C_SEARCH_TEMPLATES \
                -not \( -path '*/.*' -or -path '*/@*' \) \
                -type f \
                -name "*.$C_TEMPLATE_INFIX.*" \
    )"
    DIWU_DIR_OPT="--build-arg DIWU_DIR=${TEMP_DIR}"
fi

if [ -n "$G_SIMMULATE" ]; then
    while IFS='' read -r -d $'\n' N; do
        P="${TEMP_DIR}/${N}"
        if [ -d  "$P" ]; then
            continue
        fi
        NL=$(( $(wc -c <<<"$N") - 1 ))
        QR=$(( ( ( $C_MAX_SPLITTER - 3 ) - $NL ) / 2 ))
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

$G_SIMMULATE docker build \
    -f "$G_DOCKERFILE" \
    -t "$TIMED_TAG" \
    $ADDUSER_OPT $DIWU_DIR_OPT "$@" .

rm -rfv "$TEMP_DIR"

if [ -z "$G_NO_EXTRA_TAG" ]; then
    $G_SIMMULATE docker tag "$TIMED_TAG" "${G_IMG_NAME}:${G_EXTRA_TAG}"
fi
