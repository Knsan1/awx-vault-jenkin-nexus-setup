FROM ubuntu:latest

RUN apt-get update && apt-get install -y openssh-server sudo && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /run/sshd /home/ansible/.ssh && \
    useradd -m -s /bin/bash -G sudo ansible && \
    echo 'ansible ALL=(ALL) NOPASSWD: ALL' >> /etc/sudoers

# Copy entrypoint
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# Harden sshd
RUN sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin no/' /etc/ssh/sshd_config && \
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config && \
    sed -i 's/#PubkeyAuthentication yes/PubkeyAuthentication yes/' /etc/ssh/sshd_config

EXPOSE 22
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
