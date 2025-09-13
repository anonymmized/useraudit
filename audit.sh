#!/bin/bash
#D
set -euo pipefail

platform_user_created=0

die() { echo "❌ $*" >&2; exit 1; }

validate_username() {
    local name="${1-}"
    local maxlen=32

    [[ -n "$name" ]] || { echo "username: clear" >&2; return 1; }
    if (( ${#name} > maxlen )); then    
        echo "username: too long (>${maxlen})" >&2; return 1
    fi

    if [[ ! "$name" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
        echo "username: only [a-z0-9_-] are available, first - letter/_" >&2; return 1
    fi

    if [[ "$name" =~ ^[0-9]+$ ]]; then
        echo "username: cannot consist only of numbers" >&2; return 1
    fi

    local reserved=(
        root daemon bin sys sync mail news uucp operator games nobody nogroup
        admin guest
    )

    for r in "${reserved[@]}"; do
        [[ "$name" == "$r" ]] && { echo "username: reserved: $r" >&2; return 1; }
    done

    return 0

}

cleanup() {
  echo -e "\n⚠️   Interrupted. I do cleaning ..."
  if [[ $platform_user_created -eq 1 ]]; then
    case "$(uname -s)" in
      Linux)
        if id "$username" &>/dev/null; then
          sudo userdel -r "$username" >/dev/null 2>&1 || true
          echo "🧹 Linux: The user '$username' and his home directory were deleted."
        fi
        ;;
      Darwin)
        if id "$username" &>/dev/null; then
          /usr/sbin/sysadminctl -deleteUser "$username" -secure 2>/dev/null || true
          sudo rm -rf "/Users/$username" 2>/dev/null || true
          echo "🧹 macOS: The user '$username' and his home directory were deleted."
        fi
        ;;
    esac
  fi
  exit 130
}

trap cleanup INT TERM

sudo -v || die "We need a Sudo right"

read -r -p "Enter name for new user: " username
[[ -n "${username:-}" ]] || die "The user name cannot be empty"
[[ "$username" =~ ^[a-z_][a-z0-9_-]*$ ]] || die "The incorrect user name: '$username'"

read -r -p "Enter full name (comment): " comment

OS="$(uname -s)"

if [[ "$OS" == "Darwin" ]]; then
  home_dir="/Users/$username"
else
  home_dir="/home/$username"
fi

if id "$username" &>/dev/null; then
  die "User '$username' already exists"
fi
if [[ -e "$home_dir" && ! -d "$home_dir" ]]; then
  die "The path $home_dir already exists and this is not a catalog"
fi

create_user_linux() {
  if command -v useradd >/dev/null 2>&1; then
    sudo useradd -m -d "$home_dir" -s /bin/bash -c "$comment" "$username"
  elif command -v adduser >/dev/null 2>&1; then
    sudo adduser --disabled-password --home "$home_dir" --shell /bin/bash --gecos "$comment" "$username"
  elif [[ -x /usr/sbin/useradd ]]; then
    sudo /usr/sbin/useradd -m -d "$home_dir" -s /bin/bash -c "$comment" "$username"
  else
    die "No useradd nor adduser was found. Install shadow-utils/ passwd utils."
  fi
}

create_user_macos() {
  /usr/sbin/sysadminctl -addUser "$username" -fullName "$comment" -shell /bin/bash
  /usr/sbin/createhomedir -c -u "$username" >/dev/null
  local pg
  pg="$(id -gn "$username" 2>/dev/null || echo staff)"
  sudo chown "$username:$pg" "$home_dir"
  sudo chmod 700 "$home_dir"
}

case "$OS" in
  Linux)  create_user_linux ;;
  Darwin) create_user_macos ;;
  *)      die "Unfinished OS: $OS" ;;
esac

platform_user_created=1
echo "✅ User '$username' created on $OS"

echo "🔐 Set the password for '$username' (or click Ctrl+C for cancellation):"
sudo passwd "$username"

primary_group="$(id -gn "$username" 2>/dev/null || echo "$username")"
sudo chmod 700 "$home_dir"
sudo chown "$username:$primary_group" "$home_dir"

echo "🔎 Status of accounting:"
id "$username" || true
echo "📂 Rights to home catalog:"
ls -ld "$home_dir" || true

echo "ℹ️  Ready: shell /bin/bash, home directory '$home_dir' closed (700)."

cat <<'TIP'

👉 Additional steps (if necessary):

# (Linux) Prohibit the entrance by password-only ssh-key:
#   sudo passwd -l USERNAME

# (Linux) Create .ssh and add key:
#   sudo -u USERNAME mkdir -m 700 /home/USERNAME/.ssh
#   sudo -u USERNAME sh -c 'touch /home/USERNAME/.ssh/authorized_keys && chmod 600 /home/USERNAME/.ssh/authorized_keys'

# (Linux) Add minimal access to groups (example):
#   sudo usermod -aG dev USERNAME

# (Linux) Check the deadlines and password policy:
#   sudo chage -l USERNAME

# (macOS) Make user admin:
#   sudo dseditgroup -o edit -a USERNAME -t user admin

# (macOS) Add to Filevault (after installing a password):
#   sudo fdesetup add -usertoadd USERNAME
TIP


