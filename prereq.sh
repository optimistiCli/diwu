#!/bin/sh
/bin/bash -c '
    set -e
    uname -s | grep -i linux
    for U in bash mktemp find sed; do
        $U --version \
        | head -n 1 \
        | grep GNU
    done
    id -Gn | grep docker
    stat -c %G /var/run/docker.sock | grep docker
    echo "Looking good"
' | grep "Looking good" \
|| echo "Something is off"