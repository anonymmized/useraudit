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
        elif [[ ${pass_created:-0} -eq 1 ]]; then
            passwd -d "$NEW_USER" 2>/dev/null || true
        elif [[ ${home_created:-0} -eq 1 && "$HOME_DIR" == /home/* ]]; then
            rm -rf "$HOME_DIR"
        fi
    fi
}

start() {
    read -r -p "Enter username: " NEW_USER

    if id -u "$NEW_USER" >/dev/null 2>&1; then
        echo "User '$NEW_USER' already exists." >&2
        return 1
    fi

    user_created=0
    home_created=0
    pass_created=0
    if [[ "$OS" == "Darwin" ]]; then
        HOME_DIR="/Users/$NEW_USER"
    else 
        HOME_DIR="/home/$NEW_USER"
    fi

    trap 'cleanup' INT TERM ERR
}

create_linux_user() {
    local FULL_NAME PASS PASS2
    read -r -p "Enter full name: " FULL_NAME

    local flag=0
    while [[ $flag -eq 0 ]]; do
        read -r -s -p "Enter password for new user: " PASS; printf '\n' >&2
        if [[ ${#PASS} -lt 8 ]]; then
            echo "Password too short"
            read -e -p "Are you sure you want to continue with a short password? [Y/n]: " ANSWY; printf '\n' >&2
            case "$ANSWY" in 
                Y|y|Yes|YES|'') ;;
                N|n|No|NO) continue ;;
                *) echo "Invalid input. Please enter Y/y or N/n"; continue ;;
            esac
        fi
        read -r -s -p "Enter password again: " PASS2; printf '\n' >&2
        if [[ "$PASS" == "$PASS2" ]]; then
            flag=1
        else 
            echo "Passwords do not match. Try again"
        fi
    done
    useradd -m -c "$FULL_NAME" -s /bin/bash "$NEW_USER" > /dev/null 2>&1
    user_created=1

    HASH=$(openssl passwd -6 "$PASS")
    usermod --password "$HASH" "$NEW_USER" > /dev/null 2>&1
    pass_created=1

    unset -v PASS PASS2 HASH

    chown "$NEW_USER:$NEW_USER" "/home/$NEW_USER" > /dev/null 2>&1
    chmod 700 "/home/$NEW_USER" > /dev/null 2>&1

    usermod -aG sudo "$NEW_USER" > /dev/null 2>&1
    echo "User '$NEW_USER' was added to the admin group"

    if id "$NEW_USER" &>/dev/null; then
        echo "New user '$NEW_USER' at '$HOME_DIR' were created"
        return 0
    else 
        echo "Something went wrong"
        exit 1
    fi
    
    
}
create_macos_user() {
    local FULL_NAME PASS PASS2
    read -r -p "Enter full name: " FULL_NAME
    
    local flag=0
    while [[ $flag -eq 0 ]]; do
        read -r -s -p "Enter password for new user: " PASS; printf '\n' >&2
        if [[ ${#PASS} -lt 8 ]]; then 
            read -p "Password too short. \nYou are sure you want to continue with a short password? [Y/n] " ANSWY; printf '\n' >&2
            case "$ANSWY" in 
                Y|y|Yes|YES|'')
                    ;;
                N|n|No|NO) 
                    continue 
                    ;;
                *)
                    echo "Invalid input. Please enter Y/y or N/n."
                    continue
                    ;;
            esac
        fi
        read -r -s -p "Enter password again: " PASS2; printf '\n' >&2
        if [[ "$PASS" == "$PASS2" ]]; then
            flag=1
        else 
            echo "Passwords do not match. Try again"
        fi
    done

    /usr/sbin/sysadminctl -addUser "$NEW_USER" -fullName "$FULL_NAME" -home "$HOME_DIR" -shell "/bin/zsh" -password "$PASS" > /dev/null 2>&1
    user_created=1
    /usr/sbin/createhomedir -c -u "$NEW_USER" > /dev/null 2>&1
    home_created=1
    
    chown "$NEW_USER:$(id -gn "$NEW_USER")" "$HOME_DIR" > /dev/null 2>&1
    chmod 700 "$HOME_DIR" > /dev/null 2>&1

    unset -v PASS PASS2

    dseditgroup -o edit -a "$NEW_USER" -t user admin > /dev/null 2>&1
    echo "User "$NEW_USER" was added to the admin group"

    if id "$NEW_USER" &>/dev/null; then
        echo "New user '$NEW_USER' at '$HOME_DIR' were created"
        return 0
    else
        echo "Something went wrong"
        exit 1
    fi
    
}

change_pass() {
    local USER="$1"
    if [[ -z "$USER" ]]; then
        echo "You need to specify the user's name"
        exit 1
    fi

    if [[ "$OS" == "Darwin" ]]; then
        security set-keychain-password /Users/"$USER"/Library/Keychains/login.keychain-db 
        echo "Password for user $USER was changed"
    fi
}

get_info() {
    local USER="$1"
    if [[ -z "$USER" ]]; then
        echo "You need to specify the user's name"
        exit 1
    fi
    echo "Username : $USER"
    uid=$(id "$USER" | grep uid | awk -F'=' '{print $2}' | awk -F' ' '{print $1}' | awk -F'(' '{print $1}')
    echo "UID : $uid"
    gid=$(id "$USER" | grep gid | awk -F' ' '{print $2}' | awk -F'=' '{print $2}' | awk -F'(' '{print $1}')
    echo "GID : $gid"
    if [[ "$OS" == "Darwin" ]]; then
        user_name=$(dscl . -read /Users/"$USER" | grep RealName | awk -F': ' '{print $2}' | sed 's/^ *//')
        echo "Name : $user_name"
        home_dir=$(dscl . -read /Users/"$USER" | grep NFSHomeDirectory | awk -F': ' '{print $2}' | sed 's/^ *//')
        echo "Home directory : $home_dir"
        shell_name=$(dscl . -read /Users/"$USER" | grep UserShell | awk -F': ' '{print $3}' | sed 's/^ *//')
        echo "Shell : $shell_name"
        grps=$(groups "$USER")
        echo "Additional $USER's groups : $grps"
        last_login=$(last -1 "$USER" 2>/dev/null | head -1 | awk '{print $4, $5, $6, $7, $8}' | sed 's/^ *//')
        if [[ -n "$last_login" && "$last_login" != "never" ]]; then
            echo "Last login : $last_login"
        else 
            echo "Last login : never logged in"
        fi
    else 
        user_name=$(finger "$USER" | grep Name | awk -F': ' '{print $3}')
        echo "Name : $user_name"
        home_dir=$(finger "$USER" | grep Directory | awk -F': ' '{print $2}' | awk -F' ' '{print $1}')
        echo "Home directory : $home_dir"
        shell_name=$(finger "$USER" | grep Shell | awk -F': ' '{print $3}')
        echo "Shell : $shell_name"
        grps=$(groups "$USER" | awk -F' : ' '{print $2}')
        echo "Additional $USER's groups : $grps"
        if [[ -f /.dockerenv ]] || [[ -n "${container:-}" ]] || [[ ! -f /var/log/wtmp ]]; then
            echo "Last login : not available (running in container)"
        else
            last_login_last=$(finger "$USER" 2>/dev/null | grep Last | awk '{print $4, $5}')
            last_login_on=$(finger "$USER" 2>/dev/null | grep since | awk '{print $4, $5}')
            
            if [[ -n "$last_login_last" && "$last_login_last" != "" ]]; then
                echo "Last login : $last_login_last"
            elif [[ -n "$last_login_on" && "$last_login_on" != "" ]]; then
                echo "Last login : $last_login_on"
            else
                last_login_alt=$(last -1 "$USER" 2>/dev/null | head -1 | awk '{print $4, $5, $6, $7, $8}' | sed 's/^ *//')
                if [[ -n "$last_login_alt" && "$last_login_alt" != "never" && "$last_login_alt" != "" ]]; then
                    echo "Last login : $last_login_alt"
                else
                    echo "Last login : never logged in"
                fi
            fi
        fi
    fi
}

delete_user() {
    local USER="$1"
    if [[ -z "$USER" ]]; then
        echo "You need to specify the user's name"
        exit 1
    fi
    
    if [[ "$OS" == "Darwin" ]]; then
        local HOME_DIR_DEL="/Users/$USER"
        if id -u "$USER" >/dev/null 2>&1; then
            echo "Removing user..."
            echo "Removing from sudoers..."
            echo "-------------------------"
            /usr/sbin/sysadminctl -deleteUser "$USER" -secure > /dev/null 2>&1
        fi
        if [[ -d "$HOME_DIR_DEL" && "$HOME_DIR_DEL" == /Users/* ]]; then
            echo "Removing the home directory..."
            rm -rf "$HOME_DIR_DEL" > /dev/null 2>&1
        fi
        echo "Deleted user: '$USER'"
    else 
        if id -u "$USER" >/dev/null 2>&1; then
            userdel -f -r "$USER" > /dev/null 2>&1
            echo "Removing the home directory..."
            echo "-------------------------"
            echo "Removing from sudoers..."
            echo "Removing user..."
        fi
        echo "Deleted user: '$USER'"
    fi 
}

DO_CREATE=0
DO_DELETE=0
DO_DELETE_Y=0
DO_MONITOR=0
DO_CHANGE=0
TARGET_USER=""

while getopts ":cd:y:m:p:h" opt; do
    case $opt in
        c) DO_CREATE=1 ;;
        d) DO_DELETE=1; TARGET_USER="$OPTARG" ;;
        y) DO_DELETE_Y=1; TARGET_USER="$OPTARG" ;;
        m) DO_MONITOR=1; TARGET_USER="$OPTARG" ;;
        p) DO_CHANGE=1; TARGET_USER="$OPTARG" ;;
        h) usage; exit 0 ;;
        \?) echo "Bad option: -$OPTARG" >&2; usage; exit 1 ;;
        :) echo "Option -$OPTARG requires an argument" >&2; usage; exit 1 ;;
    esac
done
shift $((OPTIND - 1))

if [[ $DO_CREATE -eq 1 && ( $DO_DELETE -eq 1 || $DO_DELETE_Y -eq 1 ) ]]; then
    echo "You cannot use -c and -d/-y simultaneously" >&2
    usage
    exit 1
fi

if [[ $DO_DELETE -eq 1 && $DO_DELETE_Y -eq 1 ]]; then
    echo "Choose one option -d or -y" >&2
    usage
    exit 1
fi

if [[ $DO_CREATE -eq 1 ]]; then
    start
    if [[ "$OS" == "Darwin" ]]; then
        create_macos_user
    else
        create_linux_user
    fi
elif [[ $DO_DELETE -eq 1 ]]; then
    read -p "Are you really sure about deleting user '$TARGET_USER'? [Y/n] " ANS; printf '\n'>&2
    case "$ANS" in 
        Y|y|Yes|YES|'') delete_user "$TARGET_USER" ;;
        N|n|No|NO) echo "Exiting from the program"; exit 0 ;;
        *) echo "Bad answer"; exit 1 ;;
    esac

elif [[ $DO_MONITOR -eq 1 ]]; then
    get_info "$TARGET_USER"
    
elif [[ $DO_DELETE_Y -eq 1 ]]; then
    delete_user "$TARGET_USER"
elif [[ $DO_CHANGE -eq 1 ]]; then
    change_pass "$TARGET_USER"
else 
    usage 
    exit 1
fi