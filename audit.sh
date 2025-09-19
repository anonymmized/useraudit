#!/bin/bash

set -euo pipefail

OS="$(uname -s)"

if [[ $EUID -ne 0 ]]; then
    exec sudo -p "Enter password for script: " -- "$0" "$@"
fi
# Create users

create_macos_user() {
    local NEW_USER FULL_NAME PASS PASS2
    read -r -p "Enter username: " NEW_USER
    read -r -p "Enter full name: " FULL

    if id -u "$NEW_USER" >/dev/null 2>&1; then
        echo "User '$NEW_USER' already exists." >&2
        return 1
    fi
    
    flag=0
    while [[ $flag -eq 0 ]]; do
        read -r -s -p "Enter password for new user: " PASS; echo
        if [[ ${#PASS} -lt 8 ]]; then 
            echo "Password too short, enter again"
        else 
            read -r -s -p "Enter password again: " PASS2; echo
            if [[ "$PASS" -eq "$PASS2" ]]; then
                flag=1
            else 
                echo "Incorrect password. Try again"
            fi
            
        fi
    done

    sysadminctl -addUser "$NEW_USER" -fullName "$FULL_NAME" -home "/Users/$USER" -shell "/bin/zsh" -password "$PASS"
    createhomedir -c -u "$NEW_USER" >/dev/null

    chown "$NEW_USER:$(id -gn "$NEW_USER")" "/Users/$NEW_USER"
    chmod 700 "/Users/$NEW_USER"

    unset -v PASS

    if id "$NEW_USER" &>/dev/null; then
        echo "New user $NEW_USER at /Users/$NEW_USER were created"
        return 0
    else
        echo "Something went wrong"
        exit 1
    fi
}

if [[ "$OS" == "Darwin" ]]; then
    create_macos_user
fi