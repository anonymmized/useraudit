# useraudit

useraudit is a Bash script designed for managing local user accounts on Linux and macOS systems. It provides an easy command-line interface to create, delete, lock/unlock users, change passwords, manage groups, and modify user shells.

---

## Table of Contents

1. [General Info](#general-info)
2. [Features](#features)
3. [Requirements](#requirements)
4. [Installation](#installation)
5. [Usage](#usage)
6. [Commands and Options](#commands-and-options)
7. [Examples](#examples)
8. [Security](#security)
9. [Limitations](#limitations)
10. [Cleanup & Error Handling](#cleanup--error-handling)
11. [License](#license)

---

## General Info

useraudit simplifies user management tasks by abstracting platform differences between Linux and macOS and providing unified commands for administrators to manage user accounts efficiently.

---

## Features

- Add new users with prompted username, full name, and password
- Delete users (with confirmation or forced)
- Lock and unlock user accounts
- Change user passwords
- Display user information (UID, groups, last login, shell, home directory)
- Add or remove users from groups
- View and change the login shell interactively
- Works on both Linux and macOS with native commands

---

## Requirements

- Bash shell environment
- Root or sudo privileges to manage user accounts
- On macOS:
  - Uses `dscl`, `sysadminctl`, and `createhomedir` utilities
- On Linux:
  - Requires standard user management commands like `useradd`, `usermod`, `passwd`, and `userdel`

---

## Installation

1. Save the script file as `useraudit.sh`.
2. Make it executable:
```bash
chmod +x useraudit.sh
```
3. Run with root privileges (or via sudo):
```bash
sudo ./useraudit.sh [options]
```

---

## Usage

Run the script with one or more options listed below:

```bash
Usage: ./useraudit.sh [options]

Options:
-c Create new user (prompts for username, full name, password)
-a User Add specified user to a group
-r User Remove specified user from a group
-d User Delete specified user with confirmation
-y User Delete specified user without confirmation
-s View and optionally change current shell
-m User Display information on specified user
-p User Change specified user's password
-L User Lock user account
-U User Unlock user account
-h Show help/usage information
```


---

## Commands and Options

- **Create User (-c):** Prompts for username, full name, and password. Creates user and home directory. Adds user to admin group.
- **Delete User (-d, -y):** Deletes user account and home directory. `-d` asks for confirmation; `-y` deletes immediately.
- **Lock User (-L):** Disables user login (uses `passwd -l` on Linux, `dscl` on macOS).
- **Unlock User (-U):** Restores user login (uses `passwd -u` on Linux, `dscl` on macOS).
- **Change Password (-p):** Changes user password affected natively (`passwd` or macOS keychain).
- **User Info (-m):** Shows UID, GID, groups, shell, home directory, last login details.
- **Add to Group (-a User):** Lists groups and adds user to selected group.
- **Remove from Group (-r User):** Lists groups and removes user from selected group.
- **Change Shell (-s):** Displays current shell and allows selecting a new shell from `/etc/shells`.

---

## Examples

Create a new user:
```bash
sudo ./useraudit.sh -c
```

Delete a user with confirmation:
```bash
sudo ./useraudit.sh -d username
```

Lock a user account:
```bash
sudo ./useraudit.sh -L username
```

Unlock a user account:
```bash
sudo ./useraudit.sh -U username
```

Display user info:
```bash
sudo ./useraudit.sh -m username
```

Add a user to a group:
```bash
sudo ./useraudit.sh -a username
```

Change a user's password:
```bash
sudo ./useraudit.sh -p username
```

Change current user shell:
```bash
sudo ./useraudit.sh -s
```

---

## Security

- Script elevates privileges by requesting sudo if not running as root.
- Password inputs are masked and confirmed during user creation.
- Password length check with user confirmation for less than 8 characters.
- Deletion with confirmation protects from accidental data loss.

---

## Limitations

- Only tested on modern Linux distributions and macOS.
- Requires standard system utilities (`useradd`, `dscl`, etc.) to be present.
- Does not yet support bulk user operations.
- Assumes default paths for user directories (`/home` on Linux, `/Users` on macOS).

---

## Cleanup & Error Handling

- The script uses trap to rollback partial user creation in case of errors (deleting created accounts or home directories).
- Proper error messages are displayed for failed operations.

---

## License

Free to use, modify, and distribute.

---

*This README was generated to document the useraudit Bash script for system administrators managing Linux and macOS user accounts.*
