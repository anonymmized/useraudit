#!/bin/bash

set -euo pipefail

user_created=0

cleanup() {
    echo "\nCleaning..."
    if [[ $user_created -eq 1 ]]; then 
        sudo userdel -r "$username" > /dev/null 2>&1 || true
        echo "User $username was deleted" 
    fi 
    exit 130
}

trap cleanup INT TERM

sudo -v || die "Нужны sudo-права для создания пользователя"

read -r -p "Enter name for new user: " username
[[ -n "${username:-}" ]] || die "Username can't be empty" 

if [[ ! "$username" =~ ^[a-z_][a-z0-9_-]*$ ]]; then 
    die "Incorrect username: '$username'"
fi

read -r -p "Enter full name (comment): " comment

if id "$username" &>/dev/null; then 
    die "User $username is already exists" 
fi

home_dir="/home$username"
if [[ -e "$home_dir" && ! -d "$home_dir" ]]; then
    die "The path $home_dir already exists and this is not a catalog"
fi

# --- Create User ---
# -m : create home directory
# -d : a clear path to Home
# -s : shell
# -c : comment

sudo useradd -m -d "$home_dir" -s /bin/bash -c "$comment" "$username"
user_created=1
echo "✅ User '$username' created"

echo "🔐 Set the password for '$username':"
sudo passwd "$username"

sudo chmod 700 "$home_dir"
sudo chown "$username:$username" "$home_dir"

echo "🔎 Status:"
id "$username" || true

echo "📂 Rights to home catalog:"
ls -ld "$home_dir" || true

echo "ℹ️   Done. User '$username' created with interactive shell /bin/bash"
echo "     home directory '$home_dir' closed (700), owner $username:$username"

cat <<'TIP'
👉 Советы по усилению безопасности (выполняй вручную по необходимости):

# Запретить вход по паролю (оставить только SSH-ключи):
#   sudo passwd -l USERNAME

# Создать .ssh с правильными правами и добавить публичный ключ:
#   sudo -u USERNAME mkdir -m 700 /home/USERNAME/.ssh
#   sudo -u USERNAME sh -c 'touch /home/USERNAME/.ssh/authorized_keys && chmod 600 /home/USERNAME/.ssh/authorized_keys'

# Добавить в нужные группы (минимально необходимые привилегии):
#   sudo usermod -aG dev USERNAME

# Проверить политику пароля и сроки:
#   sudo chage -l USERNAME
TIP