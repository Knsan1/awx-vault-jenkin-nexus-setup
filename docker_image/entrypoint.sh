#!/bin/bash
# Fix ownership and permissions for ansible user's home directory and ssh files

# Set correct ownership and permissions on home directory
if [ -d /home/ansible ]; then
    chown -R ansible:ansible /home/ansible
    chmod 700 /home/ansible
else
    mkdir -p /home/ansible
    chown ansible:ansible /home/ansible
    chmod 700 /home/ansible
fi

# Ensure .ssh directory exists with correct permissions
if [ -d /home/ansible/.ssh ]; then
    chmod 700 /home/ansible/.ssh
else
    mkdir /home/ansible/.ssh
    chown ansible:ansible /home/ansible/.ssh
    chmod 700 /home/ansible/.ssh
fi

# Start SSH daemon in foreground
exec /usr/sbin/sshd -D -e
