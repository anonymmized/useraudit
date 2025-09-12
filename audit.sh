#!/bin/bash

read -p "Enter name for new user: " username

read -p "Enter full name (comment): " comment

sudo useradd -m -d "/home/$username" -s /bin/bash -c "$comment" "$username"

if id "$username" &>/dev/null; then 
    echo "User $username is already exists" 
    exit 1
fi
