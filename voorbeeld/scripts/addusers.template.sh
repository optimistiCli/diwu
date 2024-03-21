# Available variables:
# {{USER_NAME}}
# {{USER_ID}}
# {{USER_GROUP_ID}}

# TODO: Check if group exists
adduser -g {{USER_NAME}} -s /bin/sh -D -u {{USER_ID}} {{USER_NAME}} {{USER_GROUP_ID}}
