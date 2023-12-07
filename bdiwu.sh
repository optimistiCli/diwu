#!/bin/bash

set -e

function usage {
cat <<EOU >&2
Usage:
  $(basename "$0") [-h] [-i <image name>] [-g <group name>] 
    [-G <users group id> ] [-a <adduser template>] [-t | -T] [-s]
    [-- <extra options passed to 'docker build'>]

Builds specified image, creating users from given group.

Options:
  -h Print help and exit
  -i Image name, current dir name used if ommited
  -f Docker file, '<image name>.dockerfile' or 'Dockerfile' are used if ommited
  -g Name of the selected users group, 'docker' or 'administrators' 
     are used if ommited
  -G Id of the primary users group, '100' is used if ommited
  -a Template file for adduser script, reads ./addusers.template.sh if ommited
  -t Build time-tagged image only, do NOT tag it as latest
  -T Tag image 'test'
  -s Simmulate, just print out commands

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

while getopts ":i:f:g:G:a:htTs" OPT ; do
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
        g) # Secondary group
            SECONDARY_GROUP="$OPTARG"
            ;;
        G) # Primary group
            PRIMARY_GROUP_ID="$OPTARG"
            ;;
        a) # Adduser template
            ADDUSER_TEMPLATE="$OPTARG"
            ;;
        t) # Don't tag as lates
            NO_EXTRA_TAG=1
            ;;
        T) # Tag test
            EXTRA_TAG='test'
            ;;
        s) # Simmulate
            SIMMULATE='echo'
            ;;
    esac
done

shift $(( $OPTIND - 1 ))

PRIMARY_GROUP_ID="${PRIMARY_GROUP_ID-100}"

if [ -z "$SECONDARY_GROUP" ]; then
    for DEF_GR in docker administrators; do
        if grep -qE "^${DEF_GR}:" /etc/group; then
            SECONDARY_GROUP="$DEF_GR"
            break
        fi
    done
else
    if ! grep -qE "^${SECONDARY_GROUP}:" /etc/group; then
        brag_and_exit "Starnge secondary group: '$SECONDARY_GROUP'"
    fi
fi
if [ -z "$SECONDARY_GROUP" ]; then
    brag_and_exit "No secondary group"
fi

IMG_NAME="${IMG_NAME-$(basename "$(realpath .)")}"
if ! grep -qE '^[a-zA-Z][a-zA-Z0-9_\-]*$' <<<"$IMG_NAME"; then
    brag_and_exit "Bad image name: '$IMG_NAME"
fi

ADDUSER_TEMPLATE="${ADDUSER_TEMPLATE-addusers.template.sh}"
if ! [ -e "$ADDUSER_TEMPLATE" ]; then
    brag_and_exit "No adduser script template: '$ADDUSER_TEMPLATE'"
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

EXTRA_TAG="${EXTRA_TAG-latest}"

TIMESTAMP="$(date -u +%Y.%m.%d.%H.%M.%S)"
TIMED_TAG="${IMG_NAME}:${TIMESTAMP}"

ADDUSERS_SCRIPT="$(mktemp addusers_${TIMESTAMP}_XXXXXX)"

ADDUSERS_LIST="$(cat /etc/group \
    | grep -E "^$SECONDARY_GROUP" \
    | cut -d : -f 4 \
    | sed 's/,/\n/g'\
)"

TEMPLATE="$(grep -vE -e '^[[:blank:]]*#' -e '^[[:blank:]]*$' "$ADDUSER_TEMPLATE")"
#if [ -n "$SIMMULATE" ]; then
#    echo "======= template ======="
#    echo "$TEMPLATE"
#    echo "========================"
#fi

for VAR in USER_NAME USER_ID USER_GROUP_ID; do
    RE="${RE}"'s/\$'$VAR'/$'$VAR'/g\; '
done

while IFS='' read -r -d $'\n' LINE; do
    IFS=':' read USER_NAME _ USER_ID USER_GROUP_ID _ <<<"$LINE"
    if [ $USER_GROUP_ID -eq $PRIMARY_GROUP_ID ]; then
        if grep -Eq "^$USER_NAME$" <<<"$ADDUSERS_LIST"; then
            {
                if [ -n "$SEP" ]; then
                    echo ''
                fi
                sed "$(eval echo "$RE")" <<<"${TEMPLATE}"
            }>>"$ADDUSERS_SCRIPT"
            SEP=1
        fi
    fi;
done</etc/passwd

if [ -n "$SIMMULATE" ]; then
    echo "=== add users script ==="
    cat "$ADDUSERS_SCRIPT"
    echo "========================"
fi

$SIMMULATE docker build \
    --build-arg "ADDUSERS=${ADDUSERS_SCRIPT}" \
    -f "$DOCKERFILE" \
    -t "$TIMED_TAG" \
    "$@" .

rm -v "$ADDUSERS_SCRIPT"

if [ -z "$NO_EXTRA_TAG" ]; then
    $SIMMULATE docker tag "$TIMED_TAG" "${IMG_NAME}:${EXTRA_TAG}"
fi
