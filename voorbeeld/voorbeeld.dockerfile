FROM alpine:3.19

RUN echo Adelante amigos \
    && apk update \
    && apk add \
        vim \
    && apk cache clean \
    && echo Et voila

COPY scripts/guest/entrypoint.sh /entrypoint.sh

ARG ADDUSERS
COPY $ADDUSERS /tmp/addusers.sh

ARG DIWU_DIR
COPY $DIWU_DIR/vim.rc /etc/vim/vimrc.local

RUN echo Adelante amigos \
    && /bin/sh /tmp/addusers.sh \
    && chmod -v 444 /etc/vim/vimrc.local \
    && chmod -v 555 /entrypoint.sh \
    && echo Et voila

WORKDIR /mnt
ENTRYPOINT ["/bin/sh", "/entrypoint.sh"]
