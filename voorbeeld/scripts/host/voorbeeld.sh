#!/bin/bash

set -e

IMG_NAME="$(basename "${0%.sh}")"

GUEST_SHELL='/bin/sh'

function usage {
    local WHITES="$(basename "$0" | tr -c '' ' ')"
cat <<EOU
Usage:
  $(basename "$0") [-h] [-s] [-S | -R] [-t <tag>] [-w] [-m] [-d | -D [-l]]
  ${WHITES}[-e | -E | -k]

Run $IMG_NAME.

Options:
  -h Print help and exit
  -s Simmulate, just print out commands
  -S Run shell
  -R Run shell with root inside
  -t Another tag instaed of 'latest'
  -w Open new screen window
  -m Mount copied files for debugging
  -d Daemonize
  -l Follow container log
  -e Run docker exec
  -E Run docker exec with root inside
  -k Kill container

EOU
}

while getopts ":t:hsSRwmdDleEk" OPT ; do
    case $OPT in
        h) # Print help and exit
            usage
            exit 0
            ;;
        t) # tag
            TAG="$OPTARG"
            ;;
        s) # Simmulate
            SIMMULATE='echo'
            ;;
        S) # Shell
            RUN_SHELL="--entrypoint $GUEST_SHELL"
            ;;
        R) # Root shell
            RUN_SHELL="--entrypoint $GUEST_SHELL"
            KEEP_ROOT=1
            ;;
        w) # New screen window
            SCREEN_WINDOW="screen -t $IMG_NAME"
            ;;
        m) # Mount copies
            MOUNT_COPIES="$(egrep '^COPY[[:blank:]]+((scripts)|(config))/[^[:blank:]]+[[:blank:]]+/' "${IMG_NAME}.dockerfile" \
                | sed -E "s%^COPY[[:blank:]]*%$(pwd)/%; s%[[:blank:]]{1,}/%:/%; s/^/-v /")"
            echo ">>>$MOUNT_COPIES<<<"
            exit
            ;;
        d) # Daemonize
            DAEM_OPT='-d'
            ;;
        D) # Daemonize with terminal
            DAEM_OPT='-dt'
            ;;
        l) # Log
            LOG_F=1
            ;;
        e) # Exec
            EXEC_U=1
            ;;
        E) # Exec root
            EXEC_U=1
            KEEP_ROOT=1
            ;;
        k) # Stop
            STOP_C=1
            ;;
    esac
done

shift $(( $OPTIND - 1 ))

TAG="${TAG-latest}"

if [ -z "$KEEP_ROOT" ]; then
    USER_OPT="-u $(id -u)"
fi

if [ -n "$EXEC_U" ]; then
    if [ -n "$SCREEN_WINDOW" ]; then
        if [ -n "$USER_OPT" ]; then
            SCREEN_EXEC="${SCREEN_WINDOW}-exec"
        else
            SCREEN_EXEC="${SCREEN_WINDOW}-root"
        fi
    fi
    $SIMMULATE $SCREEN_EXEC docker exec -it $USER_OPT "$IMG_NAME" "$GUEST_SHELL"
elif  [ -n "$STOP_C" ]; then
    $SIMMULATE docker container stop "$IMG_NAME"
else
    if [ -n "$DAEM_OPT" ] && [ -n "$LOG_F" ]; then
        DAEM_AND_LOG=1
    fi

    TERM_OR_DAEM="${DAEM_OPT--it}"

    if [ -n "$SCREEN_WINDOW" ]; then
        if [ -n "$DAEM_AND_LOG" ]; then
            SCREEN_LOG="${SCREEN_WINDOW}-log"
        else
            SCREEN_RUN="${SCREEN_WINDOW}-run"
        fi
    fi

    $SIMMULATE $SCREEN_RUN docker run --rm $TERM_OR_DAEM \
        --hostname "$IMG_NAME" \
        --name "$IMG_NAME" \
        $USER_OPT $MOUNT_COPIES $RUN_SHELL "$IMG_NAME:${TAG}"

    if [ -n "$DAEM_AND_LOG" ]; then
        $SIMMULATE $SCREEN_LOG docker logs -f "$IMG_NAME"
    fi
fi