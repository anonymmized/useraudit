#!/bin/bash

set -Eeuo pipefail

OS="$(uname -s)"

if [[ $EUID -ne 0 ]]; then
        exec sudo -p "Enter password for script: " -- "$0" "$@"
fi

# ---------- helpers ----------

usage() {
    cat <<EOF
 Usage:  $0 [-c] [-d USER]

 Optinons:
    -c        Create new user (asks name, full name, password)
    -d User   Delete the specified user
    -y User   Delete the specified user with confirmation
    -h        Show this page
EOF
}

# ---------- cleanup ----------

cleanup() {
    set +e 
    trap - INT TERM ERR
    echo "Cleanup: rolling back partial changes..."

    [[ -n "${NEW_USER:-}" ]] || exit 0
    [[ -n "${HOME_DIR:-}" ]] || exit 0

    if [[ "$OS" == "Darwin" ]]; then
        if [[ ${user_created:-0} -eq 1 ]]; then
            /usr/sbin/sysadminctl -deleteUser "$NEW_USER" -secure
        elif [[ ${home_created:-0} -eq 1 && "$HOME_DIR" == /Users/* ]]; then
            rm -rf "$HOME_DIR"
        fi
    else 
        if [[ ${user_created:-0} -eq 1 ]]; then
            userdel -f -r "$NEW_USER"
        elif [[ ${home_created:-0} -eq 1 && "$HOME_DIR" == /home/* ]]; then
            rm -rf "$HOME_DIR"
        fi
    fi
}

start() {
    read -r -p "Enter username: " NEW_USER; printf '\n' >&2

    user_created=0
    home_created=0
    if [[ "$OS" == "Darwin" ]]; then
        HOME_DIR="/Users/$NEW_USER"
    else 
        HOME_DIR="/home/$NEW_USER"
    fi

    trap 'cleanup' INT TERM ERR
}


create_macos_user() {
    local FULL_NAME PASS PASS2
    read -r -p "Enter full name: " FULL_NAME

    if id -u "$NEW_USER" >/dev/null 2>&1; then
        echo "User '$NEW_USER' already exists." >&2
        return 1
    fi
    
    local flag=0
    while [[ $flag -eq 0 ]]; do
        read -r -s -p "Enter password for new user: " PASS; printf '\n' >&2
        if [[ ${#PASS} -lt 8 ]]; then 
            echo "Password too short, enter again"
            continue
        fi
        read -r -s -p "Enter password again: " PASS2; printf '\n' >&2
        if [[ "$PASS" == "$PASS2" ]]; then
            flag=1
        else 
            echo "Passwords do not match. Try again"
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
        echo "New user '$NEW_USER' at '$HOME_DIR' were created"
        return 0
    else
        echo "Something went wrong"
        exit 1
    fi
}

delete_user() {
    local USER="$1"
    if [[ -z "$TARGET_USER" ]]; then
        echo "For -d, you need to specify the user's name"
        exit 1
    fi
    
    if [[ "$OS" == "Darwin" ]]; then
        local HOME_DIR_DEL="/Users/$USER"
        if id -u "$USER" >/dev/null 2>&1; then
            /usr/sbin/sysadminctl -deleteUser "$USER" -secure
        fi
        if [[ -d "$HOME_DIR_DEL" && "$HOME_DIR_DEL" == /Users/* ]]; then
            rm -rf "$HOME_DIR_DEL"
        fi
        echo "Deleted user: '$USER'"
    else 
        if id -u "$USER" >/dev/null 2>&1; then
            userdel -f -r "$USER"
        fi
        echo "Deleted user: '$USER'"
    fi 
}

DO_CREATE=0
DO_DELETE=0
DO_DELETE_Y=0
TARGET_USER=""

while getopts ":cy:d:h" opt; do
    case $opt in
        c) 
            DO_CREATE=1
            ;;
        d) 
            DO_DELETE=1
            TARGET_USER="$OPTARG"
            ;;
        y)
            DO_DELETE_Y=1
            TARGET_USER="$OPTARG"
        h) 
            usage
            exit 0
            ;;
        \?) 
            echo "Bad option: -$OPTARG" >&2
            usage
            exit 1
            ;;
        :)
            echo "Option -$OPTARG requires an argument" >&2
            usage
            exit 1
            ;;
    esac
done
shift $((OPTIND - 1))

if [[ $DO_CREATE -eq 1 && $DO_DELETE -eq 1 && $DO_DELETE_Y -eq 1 ]]; then
    echo "You cannot use -c and -d simultaneously" >&2
    usage
    exit 1
fi

if [[ $DO_CREATE -eq 1 ]]; then
    start
    if [[ "$OS" == "Darwin" ]]; then
        create_macos_user
    else
        echo "Linux create flow not implemented yet" >&2
        exit 1
    fi
elif [[ $DO_DELETE -eq 1 ]]; then
    delete_user "$TARGET_USER"
elif [[ $DO_DELETE_Y -eq 1 ]]; then
    read -p "Are you really sure about deleting user '$TARGET_USER'? [Y/n] " ANS; printf '\n'>&2
    if [[ "$ANS" == "Y" ]]; then
        delete_user "$TARGET_USER"
    elif [[ "$ANS" == "n" ]]; then 
        echo "Exit from the program"
        exit 0
    else
        echo "Bad answer"
        exit 1
    fi
else 
    usage 
    exit 1
fi