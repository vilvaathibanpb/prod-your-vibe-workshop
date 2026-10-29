# A fake "fresh DigitalOcean droplet" created with an SSH key: Ubuntu 24.04 + systemd + sshd,
# same packages and SSH setup as DO's image. Root logs in with a key only (no root password);
# droplet.sh installs your codespace's public key when it creates the server.
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
# DO's image is a full server image: no stripped man pages, no extra "ubuntu" user
RUN rm -f /etc/dpkg/dpkg.cfg.d/excludes \
    && userdel -r ubuntu 2>/dev/null || true
RUN apt-get update && apt-get install -y --no-install-recommends \
      systemd systemd-sysv dbus openssh-server sudo ufw iptables \
      curl wget ca-certificates gnupg nano vim less man-db iproute2 iputils-ping \
      git cron rsync unzip htop lsb-release bind9-dnsutils ssh-import-id \
      unattended-upgrades needrestart apt-utils tzdata bash-completion \
    && apt-get clean && rm -rf /var/lib/apt/lists/* \
    # don't start things that make no sense in a container
    && systemctl mask systemd-logind.service getty.target console-getty.service \
         systemd-udevd.service systemd-udev-trigger.service \
    && systemctl enable ssh \
    && rm -f /usr/sbin/policy-rc.d \
    && passwd -l root >/dev/null \
    # same places DO's image sets these
    && sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config \
    && printf 'PasswordAuthentication no\n' > /etc/ssh/sshd_config.d/50-cloud-init.conf \
    && rm -f /etc/ssh/ssh_host_* \
    && echo 'droplet' > /etc/hostname

# regenerate host keys on first boot, like cloud-init does
RUN printf '[Unit]\nDescription=Generate SSH host keys\nBefore=ssh.service\nConditionPathExists=!/etc/ssh/ssh_host_ed25519_key\n[Service]\nType=oneshot\nExecStart=/usr/bin/ssh-keygen -A\n[Install]\nWantedBy=multi-user.target\n' \
      > /etc/systemd/system/ssh-hostkeys.service \
    && systemctl enable ssh-hostkeys.service

STOPSIGNAL SIGRTMIN+3
CMD ["/sbin/init"]
