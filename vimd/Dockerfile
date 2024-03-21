FROM ubuntu:rolling

RUN echo Adelante amigos \
    && export \
        DEBIAN_FRONTEND='noninteractive' \
        TZ='Antarctica/Troll' \
    && apt-get -y update \
    && apt-get -y upgrade \
    && apt-get -y dist-upgrade \
    && apt-get install -y --no-install-recommends \
        vim \
    && apt-get -y autoremove \
    && apt-get -y clean \
    && apt-get -y autoclean \
    && rm -rf /var/lib/apt/lists/* \
    && echo Et voila

ENTRYPOINT ["/usr/bin/vim"]
COPY vim.rc /etc/vim/vimrc.local

ARG ADDUSERS
COPY $ADDUSERS /tmp/addusers.sh
RUN /bin/bash /tmp/addusers.sh

