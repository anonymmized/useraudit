#!/bin/bash

set -Eeuo pipefail

OS="$(uname -s)"

if [[ $EUID -ne 0 ]]; then
    exec sudo -p "Enter password for script: " -- "$0" "$@"
fi

read -r -p "Enter username: " NEW_USER

user_created=0
home_created=0
HOME_DIR=$([[ "$OS" == "Darwin" ]] && echo "/Users/$NEW_USER" || echo "/home/$NEW_USER")

trap 'cleanup' INT TERM ERR

cleanup() {
    set +e
    trap - INT TERM ERR
    echo "The process of closing the program and deleting data has begun"

    [[ -n "${NEW_USER:-}" ]] || exit 0

    if [[ "$OS" == "Darwin" ]]; then 
        if [[ $user_created -eq 1 ]]; then 
            /usr/sbin/sysadminctl -deleteUser "$NEW_USER" -secure
        elif [[ $home_created -eq 1 && "$HOME_DIR" == /Users/* ]]; then
            rm -rf "$HOME_DIR_MAC"
        fi
    else 
        if [[ $user_created -eq 1 ]]; then 
            userdel -f -r "$NEW_USER"
        elif [[ $home_created -eq 1 && "$HOME_DIR" == /home/* ]]; then
            rm -rf "$HOME_DIR_LIN"
        fi
        
    fi
}

# Create users

create_macos_user() {
    local FULL_NAME PASS PASS2
    read -r -p "Enter full name: " FULL_NAME

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
            if [[ "$PASS" == "$PASS2" ]]; then
                flag=1
            else 
                echo "Incorrect password. Try again"
            fi
            
        fi
    done

    /usr/sbin/sysadminctl -addUser "$NEW_USER" -fullName "$FULL_NAME" -home "$HOME_DIR" -shell "/bin/zsh" -password "$PASS"
    user_created=1
    /usr/sbin/createhomedir -c -u "$NEW_USER" >/dev/null
    home_created=1
    
    chown "$NEW_USER:$(id -gn "$NEW_USER")" "$HOME_DIR"
    chmod 700 "$HOME_DIR"

    unset -v PASS PASS2

    if id "$NEW_USER" &>/dev/null; then
        echo "New user $NEW_USER at $HOME_DIR were created"
        return 0
    else
        echo "Something went wrong"
        exit 1
    fi
}

if [[ "$OS" == "Darwin" ]]; then
    create_macos_user
fi