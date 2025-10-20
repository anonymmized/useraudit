#!/bin/bash

NC=$'\033[0m'
RED=$'\033[0;31m'
PURPLE=$'\033[1;35m'
CYAN=$'\033[0;36m'
YELLOW=$'\033[1;33m'

set -Eeuo pipefail

OS="$(uname -s)"

ORIGINAL_ARGS=("$@")

password_enter() {
    if [[ $EUID -ne 0 ]]; then
        if ! sudo -n true 2>/dev/null; then
            echo -e "${RED}Enter password for script${NC}"
        fi
    exec sudo "$0" "${@:-}"
    exit $?
    fi
}

# ---------- helpers ----------

usage() {
    cat <<EOF
${YELLOW}Usage:  $0 [-c] [-d USER]

Options:
    -c        Create new user (asks name, full name, password)
    -a User   Add the specified user to the group 
    -r User   Remove the specified user from the group    
    -d User   Delete the specified user
    -y User   Delete the specified user with confirmation
    -s        View the current shell and/or change       
    -m User   Display information on the specified user
    -p User   Change the specified user password
    -L User   Lock user account
    -U User   Unlock user account
    -h        Show this page${NC}
EOF
}

# ---------- block_user ----------

block_user() {
    local USER="$1"

    if [[ "$OS" == "Darwin" ]]; then
        echo -e "${PURPLE}User $USER blocking...${NC}"
        dscl . -append /Users/"$USER" AuthenticationAuthority ";DisabledUser;" 2>/dev/null
        err_code=$(echo $?)
        if [[ $err_code -eq 0 ]]; then
            echo -e "${PURPLE}Status: Disabled${NC}"
        else 
            echo -e "${PURPLE}It was not possible to block the user. Error code: $err_code${NC}"
        fi

    else 
        echo -e "${PURPLE}User $USER blocking...${NC}"
        passwd -l "$USER" 2>/dev/null
        err_code=$(echo $?)
        if [[ $err_code -eq 0 ]]; then
            echo -e "${PURPLE}Status: Disabled${NC}"
        else 
            echo -e "${PURPLE}It was not possible to block the user. Error code: $err_code${NC}"
        fi
    fi
}

# ---------- unblock_user ----------

unblock_user() {
    local USER="$1"
    if [[ "$OS" == "Darwin" ]]; then
        echo -e "${PURPLE}Unlocking user $USER...${NC}"
        sudo dscl . -delete /Users/"$USER" AuthenticationAuthority ";DisabledUser;" 2>/dev/null
        err_code=$(echo $?)
        if [[ $err_code -eq 0 ]]; then
            echo -e "${PURPLE}Status: Unlocked${NC}"
        else 
            echo -e "${PURPLE}It was not possible to unblock the user. Error code: $err_code${NC}"
        fi
    else
        echo -e "${PURPLE}Unblocking user $USER...${NC}"
        passwd -u "$USER" 2>/dev/null
        err_code=$(echo $?)
        if [[ $err_code -eq 0 ]]; then
            echo -e "${PURPLE}Status: Unlocked${NC}" 
        else
            echo -e "${PURPLE}It was not possible to unblock the user. Error code: $err_code${NC}"
        fi
    fi
}

# ---------- cleanup ----------

cleanup() {
    set +e 
    trap - INT TERM ERR
    echo -e "${PURPLE}Cleanup: rolling back partial changes...${NC}"

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

# ---------- start ----------

start() {
    read -r -p "${PURPLE}Enter username: ${NC}" NEW_USER

    if id -u "$NEW_USER" >/dev/null 2>&1; then
        echo -e "${PURPLE}User '$NEW_USER' already exists.${NC}" >&2
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

# ---------- change_shell ----------

change_shell() {
    local active_shell=$(echo $SHELL)
    local available_shells=($(cat /etc/shells | grep '^/'))
    local i=1
    local SHLL
    local cnt=${#available_shells[@]}
    echo -e "${PURPLE}Active shell: $active_shell${NC}"

    for shell in "${available_shells[@]}"; do
        echo -e "${PURPLE}$i - $shell${NC}"
        ((i++))
    done

    read -r -p "${PURPLE}Select the shell number that you want to put: ${NC}" SHLL
    if [[ $SHLL -le $cnt && $SHLL -gt 0 ]]; then
        if [[ "$OS" == "Darwin" ]]; then
            local selected_shell="${available_shells[$((SHLL - 1))]}"
            echo -e "${PURPLE}A shift in the shell is performed...${NC}"
            chsh -s "$selected_shell"
            echo -e "${PURPLE}The shell was successfully changed${NC}"
        else 
            local selected_shell="${available_shells[$((SHLL - 1))]}"
            echo -e "${PURPLE}A shift in the shell is performed...${NC}"
            chsh -s "$selected_chell"
            echo -e "${PURPLE}The shell was successfully changed${NC}"
        fi
    fi
}

# ---------- remove_from_group ----------

remove_from_group() {
    local USER="$1"
    local GROUPP
    local groups_array=($(groups))
    local cnt=${#groups_array[@]}
    local i=1

    for group in "${groups_array[@]}"; do
        echo "$i - $group"
        ((i++))
    done

    read -r -p "${PURPLE}Enter the group number from where you want to delete a specialized user: ${NC}" GROUPP
    if [[ "$OS" == "Darwin" ]]; then
        if [[ $GROUPP -le $cnt && $GROUPP -gt 0 ]]; then
            local selected_group="${groups_array[$((GROUPP - 1))]}"
            echo -e "${PURPLE}Removing user $USER from group $selected_group...${NC}"
            dscl . -delete /Groups/"$selected_group" GroupMembership "$USER"
            echo -e "${PURPLE}User $USER removed from group $selected_group${NC}"
        else 
            echo -e "${PURPLE}Invalid group number${NC}"
        fi
    else 
        if [[ $GROUPP -le $cnt && $GROUPP -gt 0 ]]; then
            local selected_group="${groups_array[$((GROUPP - 1))]}"
            echo -e "${PURPLE}Removing user $USER from group $selected_group${NC}"
            gpasswd -d "$USER" "$selected_group"
            echo -e "${PURPLE}User $USER removed from group $selected_group${NC}"
        else
            echo -e "${PURPLE}Invalid group number${NC}"
        fi
        

    fi
}

# ---------- add_to_group ----------

add_to_group() {
    local USER="$1"
    local GROUPP
    local groups_array=($(groups))
    local cnt=${#groups_array[@]}
    local i=1

    for group in "${groups_array[@]}"; do
        echo "$i - $group"
        ((i++))
    done

    read -r -p "${PURPLE}Enter the number of the group where you need to add the specified user: ${NC}" GROUPP
    if [[ "$OS" == "Darwin" ]]; then
        if [[ $GROUPP -le $cnt && $GROUPP -gt 0 ]]; then
            local selected_group="${groups_array[$((GROUPP - 1))]}"
            echo -e "${PURPLE}Adding user $USER to group $selected_group...${NC}"
            dscl . -append /Groups/"$selected_group" GroupMembership "$USER"
            echo -e "${PURPLE}User $USER added to group $selected_group${NC}"
        else 
            echo -e "${PURPLE}Invalid group number${NC}"
        fi
    else 
        if [[ $GROUPP -le $cnt && $GROUPP -gt 0 ]]; then
            local selected_group="${groups_array[$((GROUPP - 1))]}"
            echo -e "${PURPLE}Adding user $USER to group $selected_group${NC}"
            usermod -aG "$selected_group" "$USER"
            echo -e "${PURPLE}User $USER added to group $selected_group${NC}"
        else 
            echo -e "${PURPLE}Invalid group number${NC}"
        fi
    fi
    
}

# ---------- create_user ----------

create_user() {
    local FULL_NAME PASS PASS2
    read -r -p "${PURPLE}Enter full name: ${NC}" FULL_NAME
    
    local flag=0
    if [[ "$OS" == "Darwin" ]]; then

        while [[ $flag -eq 0 ]]; do
            read -r -s -p "${PURPLE}Enter password for new user: ${NC}" PASS; printf '\n' >&2
            if [[ ${#PASS} -lt 8 ]]; then 
                read -p "${PURPLE}Password too short. \nYou are sure you want to continue with a short password? [Y/n] ${NC}" ANSWY; printf '\n' >&2
                case "$ANSWY" in 
                    Y|y|Yes|YES|'')
                        ;;
                    N|n|No|NO) 
                        continue 
                        ;;
                    *)
                        echo -e "${PURPLE}Invalid input. Please enter Y/y or N/n.${NC}"
                        continue
                        ;;
                esac
            fi
            read -r -s -p "${PURPLE}Enter password again: ${NC}" PASS2; printf '\n' >&2
            if [[ "$PASS" == "$PASS2" ]]; then
                flag=1
            else 
                echo -e "${PURPLE}Passwords do not match. Try again${NC}"
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
        echo -e "${PURPLE}User "$NEW_USER" was added to the admin group${NC}"

        if id "$NEW_USER" &>/dev/null; then
            echo -e "${PURPLE}New user '$NEW_USER' at '$HOME_DIR' were created${NC}"
            return 0
        else
            echo -e "${PURPLE}Something went wrong${NC}"
            exit 1
        fi
    else 
        local flag=0
        while [[ $flag -eq 0 ]]; do
            read -r -s -p "${PURPLE}Enter password for new user: ${NC}" PASS; printf '\n' >&2
            if [[ ${#PASS} -lt 8 ]]; then
                echo -e "${PURPLE}Password too short${NC}"
                read -e -p "${PURPLE}Are you sure you want to continue with a short password? [Y/n]: ${NC}" ANSWY; printf '\n' >&2
                case "$ANSWY" in 
                    Y|y|Yes|YES|'') ;;
                    N|n|No|NO) continue ;;
                    *) echo -e "${PURPLE}Invalid input. Please enter Y/y or N/n${NC}"; continue ;;
                esac
            fi
            read -r -s -p "${PURPLE}Enter password again: ${NC}" PASS2; printf '\n' >&2
            if [[ "$PASS" == "$PASS2" ]]; then
                flag=1
            else 
                echo -e "${PURPLE}Passwords do not match. Try again${NC}"
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
        echo -e "${PURPLE}User '$NEW_USER' was added to the admin group${NC}"

        if id "$NEW_USER" &>/dev/null; then
            echo -e "${PURPLE}New user '$NEW_USER' at '$HOME_DIR' were created${NC}"
            return 0
        else 
            echo -e "${PURPLE}Something went wrong${NC}"
            exit 1
        fi
    fi
}

# ---------- change_pass ----------

change_pass() {
    local USER="$1"
    if [[ -z "$USER" ]]; then
        echo -e "${PURPLE}You need to specify the user's name${NC}"
        exit 1
    fi

    if [[ "$OS" == "Darwin" ]]; then
        security set-keychain-password /Users/"$USER"/Library/Keychains/login.keychain-db 
        if [[ $? -eq 0 ]]; then
            echo -e "${PURPLE}Password for user $USER was changed${NC}"    
        else 
            echo -e "${PURPLE}Something went wrong${NC}"
        fi
    else 
        passwd "$USER"
        if [[ $? -eq 0 ]]; then
            echo -e "${PURPLE}Password for user $USER was changed${NC}"
        else 
            echo -e "${PURPLE}Something went wrong${NC}"
        fi
    fi
}

# ---------- get_info ----------

get_info() {
    local USER="$1"
    if [[ -z "$USER" ]]; then
        echo -e "${PURPLE}You need to specify the user's name${NC}"
        exit 1
    fi
    echo -e "${PURPLE}Username : $USER${NC}"
    uid=$(id -u "$USER")
    echo -e "${PURPLE}UID : $uid${NC}"
    gid=$(id -g "$USER")
    echo -e "${PURPLE}GID : $gid${NC}"
    if [[ "$OS" == "Darwin" ]]; then
        user_name=$(dscl . -read /Users/"$USER" | grep RealName | awk -F': ' '{print $2}' | sed 's/^ *//')
        echo -e "${PURPLE}Name : $user_name${NC}"
        home_dir=$(dscl . -read /Users/"$USER" | grep NFSHomeDirectory | awk -F': ' '{print $2}' | sed 's/^ *//')
        echo -e "${PURPLE}Home directory : $home_dir${NC}"
        shell_name=$(dscl . -read /Users/"$USER" | grep UserShell | awk -F': ' '{print $3}' | sed 's/^ *//')
        echo -e "${PURPLE}Shell : $shell_name${NC}"
        grps=$(groups "$USER")
        echo -e "${PURPLE}Additional $USER's groups : $grps${NC}"
        last_login=$(last -1 "$USER" 2>/dev/null | head -1 | awk '{print $4, $5, $6, $7, $8}' | sed 's/^ *//')
        if [[ -n "$last_login" && "$last_login" != "never" ]]; then
            echo -e "${PURPLE}Last login : $last_login${NC}"
        else 
            echo -e "${PURPLE}Last login : never logged in${NC}"
        fi
    else 
        user_name=$(finger "$USER" | grep Name | awk -F': ' '{print $3}')
        echo -e "${PURPLE}Name : $user_name${NC}"
        home_dir=$(finger "$USER" | grep Directory | awk -F': ' '{print $2}' | awk -F' ' '{print $1}')
        echo -e "${PURPLE}Home directory : $home_dir${NC}"
        shell_name=$(finger "$USER" | grep Shell | awk -F': ' '{print $3}')
        echo -e "${PURPLE}Shell : $shell_name${NC}"
        grps=$(groups "$USER" | awk -F' : ' '{print $2}')
        echo -e "${PURPLE}Additional $USER's groups : $grps${NC}"
        if [[ -f /.dockerenv ]] || [[ -n "${container:-}" ]] || [[ ! -f /var/log/wtmp ]]; then
            echo -e "${PURPLE}Last login : not available (running in container)${NC}"
        else
            last_login_last=$(finger "$USER" 2>/dev/null | grep Last | awk '{print $4, $5}')
            last_login_on=$(finger "$USER" 2>/dev/null | grep since | awk '{print $4, $5}')
            
            if [[ -n "$last_login_last" && "$last_login_last" != "" ]]; then
                echo -e "${PURPLE}Last login : $last_login_last${NC}"
            elif [[ -n "$last_login_on" && "$last_login_on" != "" ]]; then
                echo -e "${PURPLE}Last login : $last_login_on${NC}"
            else
                last_login_alt=$(last -1 "$USER" 2>/dev/null | head -1 | awk '{print $4, $5, $6, $7, $8}' | sed 's/^ *//')
                if [[ -n "$last_login_alt" && "$last_login_alt" != "never" && "$last_login_alt" != "" ]]; then
                    echo -e "${PURPLE}Last login : $last_login_alt${NC}"
                else
                    echo -e "${PURPLE}Last login : never logged in${NC}"
                fi
            fi
        fi
    fi
}

# ---------- delete_user ----------

delete_user() {
    local USER="$1"
    if [[ -z "$USER" ]]; then
        echo -e "${PURPLE}You need to specify the user's name${NC}"
        exit 1
    fi
    
    if [[ "$OS" == "Darwin" ]]; then
        local HOME_DIR_DEL="/Users/$USER"
        if id -u "$USER" >/dev/null 2>&1; then
            echo -e "${RED}Removing user...${NC}"
            echo -e "${RED}Removing from sudoers...${NC}"
            echo -e "${CYAN}-------------------------${NC}"
            /usr/sbin/sysadminctl -deleteUser "$USER" -secure > /dev/null 2>&1
        fi
        if [[ -d "$HOME_DIR_DEL" && "$HOME_DIR_DEL" == /Users/* ]]; then
            echo -e "${RED}Removing the home directory...${NC}"
            rm -rf "$HOME_DIR_DEL" > /dev/null 2>&1
        fi
        echo -e "${RED}Deleted user: '$USER'${NC}"
    else 
        if id -u "$USER" >/dev/null 2>&1; then
            userdel -f -r "$USER" > /dev/null 2>&1
            echo -e "${RED}Removing the home directory...${NC}"
            echo -e "${CYAN}-------------------------${NC}"
            echo -e "${RED}Removing from sudoers...${NC}"
            echo -e "${RED}Removing user...${NC}"
        fi
        echo -e "${NC}Deleted user: '$USER'${NC}"
    fi 
}

# ---------- Processing of arguments ----------

DO_CREATE=0
DO_DELETE=0
DO_DELETE_Y=0
DO_MONITOR=0
DO_CHANGE=0
DO_ADD_T_GROUP=0
DO_REMOVE_GROUP=0
DO_CHANGE_SHELL=0
DO_LOCK=0
DO_UNLOCK=0
TARGET_USER=""
# TARGET_GROUP=""

while getopts ":ca:r:d:y:m:p:sL:U:h" opt; do
    case $opt in
        c) DO_CREATE=1 ;;
        a) 
            DO_ADD_T_GROUP=1
            TARGET_USER="$OPTARG"
            # shift $((OPTIND - 1))
            # if [[ $# -gt 0 && $1 != -* ]]; then
            #     TARGET_GROUP="$1"
            # fi
            ;;
        r) DO_REMOVE_GROUP=1; TARGET_USER="$OPTARG" ;;
        d) DO_DELETE=1; TARGET_USER="$OPTARG" ;;
        y) DO_DELETE_Y=1; TARGET_USER="$OPTARG" ;;
        m) DO_MONITOR=1; TARGET_USER="$OPTARG" ;;
        L) DO_LOCK=1; TARGET_USER="$OPTARG" ;;
        U) DO_UNLOCK=1; TARGET_USER="$OPTARG" ;;
        p) DO_CHANGE=1; TARGET_USER="$OPTARG" ;;
        s) DO_CHANGE_SHELL=1 ;;
        h) usage; exit 0 ;;
        \?) echo -e "${RED}Bad option: -$OPTARG${NC}" >&2; usage; exit 1 ;;
        :) echo -e "${RED}Option -$OPTARG requires an argument${NC}" >&2; usage; exit 1 ;;
    esac
done
shift $((OPTIND - 1))

NEED_SUDO=0
if [[ $DO_CREATE -eq 1 || $DO_DELETE -eq 1 || $DO_DELETE_Y -eq 1 || $DO_LOCK -eq 1 || $DO_UNLOCK -eq 1 || $DO_ADD_T_GROUP -eq 1 || $DO_REMOVE_GROUP -eq 1 || $DO_CHANGE -eq 1 || $DO_CHANGE_SHELL -eq 1 ]]; then
    NEED_SUDO=1
fi

# Только если действительно нужна привилегия — запрашиваем пароль (и перезапускаем через sudo с оригинальными аргументами)
if [[ $NEED_SUDO -eq 1 ]]; then
    password_enter "${ORIGINAL_ARGS[@]}"
fi

if [[ $DO_CREATE -eq 1 && ( $DO_DELETE -eq 1 || $DO_DELETE_Y -eq 1 ) ]]; then
    echo -e "${RED}You cannot use -c and -d/-y simultaneously${NC}" >&2
    usage
    exit 1
fi

if [[ $DO_DELETE -eq 1 && $DO_DELETE_Y -eq 1 ]]; then
    echo -e "${RED}Choose one option -d or -y${NC}" >&2
    usage
    exit 1
fi

if [[ $DO_CREATE -eq 1 ]]; then
    start
    create_user
elif [[ $DO_DELETE -eq 1 ]]; then
    read -p "${PURPLE}Are you really sure about deleting user '$TARGET_USER'? [Y/n] ${NC}" ANS; printf '\n'>&2
    case "$ANS" in 
        Y|y|Yes|YES|'') delete_user "$TARGET_USER" ;;
        N|n|No|NO) echo -e "${PURPLE}Exiting from the program${NC}"; exit 0 ;;
        *) echo -e "${RED}Bad answer${NC}"; exit 1 ;;
    esac

elif [[ $DO_LOCK -eq 1 ]]; then
    block_user "$TARGET_USER"

elif [[ $DO_UNLOCK -eq 1 ]]; then
    unblock_user "$TARGET_USER"

elif [[ $DO_MONITOR -eq 1 ]]; then
    get_info "$TARGET_USER"

elif [[ $DO_ADD_T_GROUP -eq 1 ]]; then
    add_to_group "$TARGET_USER"

elif [[ $DO_REMOVE_GROUP -eq 1 ]]; then
    remove_from_group "$TARGET_USER"
    
elif [[ $DO_DELETE_Y -eq 1 ]]; then
    delete_user "$TARGET_USER"

elif [[ $DO_CHANGE_SHELL -eq 1 ]]; then
    change_shell

elif [[ $DO_CHANGE -eq 1 ]]; then
    change_pass "$TARGET_USER"

else 
    usage 
    exit 1
fi