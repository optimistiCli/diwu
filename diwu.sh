#!/bin/bash 

set -e

# Global constants

C_TEMPLATE_INFIX='template'
C_ADDUSERS_FILE_NAME="addusers.$C_TEMPLATE_INFIX.sh"
C_SEARCH_HOST_SIDE_GROUP='
    docker
    administrators
'
C_DEFAULT_GUEST_SIDE_GID=100
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
C_ADDUSERS_VARS='
    USER_NAME 
    USER_ID 
    USER_GROUP_ID
'
C_VARS_FILE_SUFFIX='vars.ini'
# Shuld be an even number
C_MAX_SPLITTER=72

# Functions

usage () {
cat <<EOU >&2
Usage:
  $(basename "$0") [-h] [-s] [-i <image name>] [-g <group name>]
    [-G <users group id> ] [-a <addusers template> | -A] [-t <tag> | -T]
    [-e <vars file> | -E] [-L] [-K] [-- <extra docker build options>]

Builds specified docker image, creating users from given group.

Options:
  -h Print help and exit
  -s Simulate, just print out commands
  -i Image name, current dir name used if omitted
  -f Docker file, if omitted looks for:
     '<image name>.dockerfile', 'Dockerfile'
  -g Name of the selected host-side users group, if omitted tries using:
     $(present_list "$C_SEARCH_HOST_SIDE_GROUP")
  -G Id of the guest-side primary users group, if omitted $C_DEFAULT_GUEST_SIDE_GID is used; special 
     value 'u[ser]' means the host-side main group of particular user is used;
     gpecial value 'g[roup]' means the source group (the one specified with -g
     option) is used
  -a Addusers script template, if omitted looks for '$C_ADDUSERS_FILE_NAME' in:
     $(present_list "$C_SEARCH_ADDUSERS")
  -A Do not generate addusers script
  -t Tag image something else instead of 'latest'
  -T Build time-tagged image only, do NOT tag it as 'latest'
  -e File defining variables for extra templates, if omitted looks for:
     '<image name>.$C_VARS_FILE_SUFFIX'
  -E Do not process templates
  -L List images with timed tag only and exit
  -K Do NOT use BuildKit

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

function get_host_group_id {
    sed -nE " \
        /^${G_HOST_SIDE_GROUP}:/{ \
            s/^([^:]*:){2}([^:]{1,}).*$/\2/; \
            p; \
            q; \
        } \
    " \
    /etc/group
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
        IFS='=' read -r VAR_NAME VALUE <<<"$VAR_EQ"
        echo -n "s%{{${VAR_NAME}}}%$(sed 's/%/\\%/g' <<<"$VALUE")%g; "
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
    local IMAGES="$( \
        docker image ls \
        | sed -nE " \
            /^${G_IMG_NAME}[[:blank:]]/{ \
                s/[[:blank:]]{1,}/:/2; \
                s/^([^[:blank:]]{1,})[[:blank:]]*([^[:blank:]]{1,}).*/\1:\2/;
                p; \
        }"
    )"
    local IN_RE="$( \
        sed -nE '
            /:[0-9]{4}(\.[0-9]{2}){5}:/!{
                s/^.*://;
                H;
            }
            ${
                g;
                s/^\n//;
                s/\n/)|(/g;
                p;
            }
        ' <<<"$IMAGES" \
    )"
    sed -nE " \
        /:(${IN_RE})$/!{
            s/:[^:]{1,}$//;
            p;
        }
    " <<<"$IMAGES"
}

function setup_img_name {
    G_IMG_NAME="${G_IMG_NAME-$(basename "$(realpath .)")}"
    if ! egrep -q '^[a-zA-Z][a-zA-Z0-9_\-]*$' <<<"$G_IMG_NAME"; then
        brag_and_exit "Bad image name: '$G_IMG_NAME'"
    fi
}

function setup_addusers_template_file {
    if [ -z "$G_ADDUSERS_TEMPLATE_FILE" ]; then
        for DIR in $C_SEARCH_ADDUSERS; do
            local CANDIDATE="${DIR}/${C_ADDUSERS_FILE_NAME}"
            if [ -e "$CANDIDATE" ]; then
                G_ADDUSERS_TEMPLATE_FILE="$CANDIDATE"
                break
            fi
        done
    else
        if ! [ -e "$G_ADDUSERS_TEMPLATE_FILE" ]; then
            brag_and_exit "No addusers script template: '$G_ADDUSERS_TEMPLATE_FILE'"
        fi
    fi

    if [ -z "$G_ADDUSERS_TEMPLATE_FILE" ]; then
        moan_and_keep_going "No addusers script template found"
        G_NO_ADDUSERS=1
    fi
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
    G_HOST_SIDE_GROUP_ID=$(get_host_group_id)
}

function setup_guest_gid {
    if [ -z "$G_GUEST_SIDE_GID" ]; then
        G_GUEST_SIDE_GID="$C_DEFAULT_GUEST_SIDE_GID"
    elif egrep -qi '^u' <<<"$G_GUEST_SIDE_GID"; then
        G_GUEST_SIDE_GID='U'
    elif egrep -qi '^g' <<<"$G_GUEST_SIDE_GID"; then
        G_GUEST_SIDE_GID="$G_HOST_SIDE_GROUP_ID"
    elif [ "$G_GUEST_SIDE_GID" != "$(tr -dc 0-9 <<<"$G_GUEST_SIDE_GID")" ]; then
        brag_and_exit "Strange guest-side GID: '$G_GUEST_SIDE_GID'"
    fi
}

function run_while_can_cook_addusers {
    while [ -n "$1" ] && [ -z "$G_NO_ADDUSERS" ]; do
        "$1"
        shift
    done
}

function setup_dockerfile {
    if [ -z "$G_DOCKERFILE" ]; then
        for CANDIDATE in \
            "${G_IMG_NAME}.dockerfile" \
            "${G_IMG_NAME}.Dockerfile" \
            Dockerfile
        do
            if [ -e "$CANDIDATE" ]; then
                G_DOCKERFILE="$CANDIDATE"
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
}

function setup_extra_tag {
    if [ -n "$G_EXTRA_TAG" ]; then
        if ! egrep -q '^[a-zA-Z0-9_][a-zA-Z0-9_\.\-]{,127}$' <<<"$G_EXTRA_TAG"; then
            brag_and_exit "Strange tag: '$G_EXTRA_TAG'"
        fi
    else
        G_EXTRA_TAG='latest'
    fi
}

function setup_vars_file {
    if [ -n "$G_VARS_FILE" ]; then
        if ! [ -e "$G_VARS_FILE" ]; then
            brag_and_exit "Strange variables file: '$G_VARS_FILE'"
        fi
    else
        G_VARS_FILE="${G_IMG_NAME}.$C_VARS_FILE_SUFFIX"
        if ! [ -e "$G_VARS_FILE" ]; then
            moan_and_keep_going "No variables file found, extra templates will not be processed"
            G_NO_TEMPLATES=1
        fi
    fi
}

function cook_timed_tag {
    G_TIME_TAGGED="${G_IMG_NAME}:$( \
        date -u +%Y.%m.%d.%H.%M.%S \
    )"
}

function cook_temp_dir {
    G_TEMP_DIR="$( \
        mktemp -d ".$( \
            echo -n "diwu_${G_TIME_TAGGED}_XXXXXX" \
            | tr -cs 'a-zA-Z0-9' '_' \
        )" \
    )"
}

function cook_addusers_script_name {
    G_ADDUSERS_SCRIPT_NAME="$( \
        detemplate_name "$C_ADDUSERS_FILE_NAME" \
    )"
}

function list_group_users {
    {
        sed -nE " \
            /^${G_HOST_SIDE_GROUP}:/{ \
                s/^([^:]*:){3}([^:]{1,}).*$/\2/; \
                s/,/\n/g; \
                p; \
                q; \
            } \
        " \
        /etc/group
        sed -nE " \
            /^([^:]*:){3}${G_HOST_SIDE_GROUP_ID}:/{ \
                s/:.*//; \
                p; \
            } \
        " \
        /etc/passwd
    } | sort -u
}

function cook_addusers_script {
    local PATH_TO_SCRIPT="${G_TEMP_DIR}/${G_ADDUSERS_SCRIPT_NAME}"
    local TEMPLATE="$( \
        egrep -v \
            '^[[:blank:]]*(#.*)?$' \
            "$G_ADDUSERS_TEMPLATE_FILE" \
    )"
    local RAW_RE="$( \
        sed -E \
            's/([^[:blank:]]{1,})/\1 = $\1/' \
            <<<"$C_ADDUSERS_VARS" \
            | cook_template_re \
    )"
    for VAR_NAME in $C_ADDUSERS_VARS; do
        local $VAR_NAME
    done
    local BUFFER
    local VARS_TO_READ=$( \
        echo $C_ADDUSERS_VARS \
        | sed 's/[[:blank:]]/ _ /; s/$/ _/' \
    )
    local GROUP_USERS_LIST="$(list_group_users)"
    while IFS='' read -r -d $'\n' PASSWD_LINE; do
        IFS=':' read $VARS_TO_READ <<<"$PASSWD_LINE"
        if [ $USER_ID -ne 0 ] \
            && egrep -q "^$USER_NAME$" <<<"$GROUP_USERS_LIST"
        then
            if [ "$G_GUEST_SIDE_GID" != 'U' ]; then
                USER_GROUP_ID="$G_GUEST_SIDE_GID"
            fi
            BUFFER="${BUFFER+${BUFFER}$'\n\n'}"
            BUFFER="${BUFFER}$( \
                sed \
                    "$(eval "echo \"$RAW_RE\"")" \
                    <<<"$TEMPLATE" \
            )"
        fi
    done </etc/passwd
    if [ -n "$BUFFER" ]; then
        echo "$BUFFER" > "$PATH_TO_SCRIPT"
        G_ADDUSERS_OPT="--build-arg ADDUSERS=${PATH_TO_SCRIPT}"
    else
        moan_and_keep_going "No users for the addusers script found"
        G_NO_ADDUSERS=1
    fi
}

function cook_extra_templates {
    local RE="$(cook_template_re <"$G_VARS_FILE")"

    while IFS='' read -r -d $'\n' TEMPLATE_FILE; do
        local COOKED_FILE_NAME="$(detemplate_name "$(basename $TEMPLATE_FILE)")"
        if [ "$COOKED_FILE_NAME" = "$G_ADDUSERS_SCRIPT_NAME" ]; then
            moan_and_keep_going "Prevented cooking addusers script from alternative template"
            continue
        fi
        local COOKED_FILE="${G_TEMP_DIR}/${COOKED_FILE_NAME}"
        if [ -e "$COOKED_FILE" ]; then
            moan_and_keep_going "Prevented overwriting cooked file: '$COOKED_FILE_NAME'"
            continue
        fi
        sed "$RE" <"$TEMPLATE_FILE" >"$COOKED_FILE"
    done <<<"$( \
        find $C_SEARCH_TEMPLATES \
                -not \( -path '*/.*' -or -path '*/@*' \) \
                -type f \
                -name "*.$C_TEMPLATE_INFIX.*" \
    )"
    G_DIWU_DIR_OPT="--build-arg DIWU_DIR=${G_TEMP_DIR}"
}

function dump_generated {
    while IFS='' read -r -d $'\n' NAME; do
        local FILE="${G_TEMP_DIR}/${NAME}"
        if [ -d  "$FILE" ]; then
            continue
        fi
        local NUM_LETTERS=$(( $(wc -c <<<"$NAME") - 1 ))
        local LEN_LEFT
        local LEN_RIGHT=$(( ( ( $C_MAX_SPLITTER - 3 ) - $NUM_LETTERS ) / 2 ))
        if [ $(( $NUM_LETTERS % 2 )) -eq 0 ]; then
            # Even
            LEN_LEFT=$LEN_RIGHT
        else
            # Odd
            LEN_LEFT=$(( $LEN_RIGHT - 1 ))
        fi
        if [ $LEN_LEFT -lt 3 ]; then
            LEN_LEFT=3
            LEN_RIGHT=3
        fi
        local TOP_SEPARATOR="$(print_eqs $LEN_LEFT) $NAME $(print_eqs $LEN_RIGHT)"
        echo ">$TOP_SEPARATOR<";
        cat "$FILE"
        echo ">$(print_eqs $(( $(wc -c <<<"$TOP_SEPARATOR") - 1 )) )<"
    done <<<"$(ls -1 $G_TEMP_DIR)"
}

function cook_image {
    if [ -z "$G_NO_BUILDKIT" ]; then
        export DOCKER_BUILDKIT=1 \
            BUILDKIT_PROGRESS=plain
    fi
    $G_SIMMULATE docker build \
        -f "$G_DOCKERFILE" \
        -t "$G_TIME_TAGGED" \
        $G_ADDUSERS_OPT $G_DIWU_DIR_OPT "$@" .
}

function clean_up {
    rm -rfv "$G_TEMP_DIR"
}

function assign_extra_tag {
    $G_SIMMULATE docker tag "$G_TIME_TAGGED" "${G_IMG_NAME}:${G_EXTRA_TAG}"
}

# Read command line options

while getopts ":i:f:g:G:a:t:e:ThEsALK" OPT; do
    case $OPT in
        h) # Print help and exit
            usage
            exit 0
            ;;
        i) # Image name
            G_IMG_NAME="${OPTARG%.?ockerfile}"
            ;;
        f) # Dockerfile
            G_DOCKERFILE="$OPTARG"
            ;;
        g) # Host-side group
            G_HOST_SIDE_GROUP="$OPTARG"
            ;;
        G) # Guest-side group id
            G_GUEST_SIDE_GID="$OPTARG"
            ;;
        a) # Addusers template
            G_ADDUSERS_TEMPLATE_FILE="$OPTARG"
            ;;
        A) # No addusers
            G_NO_ADDUSERS=1
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
        E) # No templates
            G_NO_TEMPLATES=1
            ;;
        s) # Simmulate
            G_SIMMULATE='echo'
            ;;
        L) # List anonymous timed tags
            G_LIST_ANONYMS_AND_EXIT=1
            ;;
        K) # Don't use BuildKit
            G_NO_BUILDKIT=1
            ;;
    esac
done

shift $(( $OPTIND - 1 ))

# Check for sanity and set everithing up

setup_img_name
if [ -n "$G_LIST_ANONYMS_AND_EXIT" ]; then
    list_anonyms
    exit 0
fi
run_while_can_cook_addusers \
    setup_addusers_template_file \
    setup_host_group \
    setup_guest_gid
setup_dockerfile
setup_extra_tag
if [ -z "$G_NO_TEMPLATES" ]; then
    setup_vars_file
fi

# Start cooking

cook_timed_tag
cook_temp_dir
cook_addusers_script_name
if [ -z "$G_NO_ADDUSERS" ]; then
    cook_addusers_script
fi
if [ -z "$G_NO_TEMPLATES" ]; then
    cook_extra_templates
fi
if [ -n "$G_SIMMULATE" ]; then
    dump_generated
fi
cook_image "$@"
if [ -z "$G_NO_EXTRA_TAG" ]; then
    assign_extra_tag
fi
clean_up
