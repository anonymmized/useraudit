#!/bin/bash

set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    exec sudo -p "Enter password for script: " -- "$0" "$@"
fi
# Create users

create_macos_user() {
    local NEW_USER FULL_NAME PASS
    read -r -p "Enter username: " NEW_USER
    read -r -p "Enter full name: " FULL

    if id -u "$NEW_USER" >/dev/null 2>&1; then
        echo "User '$NEW_USER' already exists." >&2
        return 1
    fi

    read -r -s -p "Enter password for new user: " PASS; echo

    sysadminctl -addUser "$NEW_USER" -fullName "$FULL_NAME" -home "/Users/$USER" -shell "/bin/zsh" -password "$PASS"
    createhomedir -c -u "$NEW_USER" >/dev/null

    chown "$NEW_USER:$(id -gn "$NEW_USER")" "/Users/$NEW_USER"
    chmod 700 "/Users/$NEW_USER"

    unset -v PASS

    echo "New user $NEW_USER at /Users/$NEW_USER were created"
}   

create_macos_user