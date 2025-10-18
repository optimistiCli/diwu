#!/bin/sh
/bin/bash -c '
    set -e
    echo -n "Checking OS: " >&2
    uname -s \
        | grep -i linux >&2
    for U in bash mktemp find sed; do
        echo -n "Checking $U command: " >&2
        which $U >/dev/null
        $U --version \
        | head -n 1 \
        | grep -e GNU -e coreutils >&2
    done
    echo -n "Checking current user groups: " >&2
    id -Gn \
        | tr -s "[[:space:]]" "\n" \
        | grep docker >&2
    echo -n "Checking docker.sock: " >&2
    stat -c %G /var/run/docker.sock \
        | grep docker >&2
    echo "Looking good"
' \
    | grep "Looking good" \
    || echo "Something is off"
