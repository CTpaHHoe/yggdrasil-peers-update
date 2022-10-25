#!/usr/bin/env bash

cp yggdrasil-peers-{parse,update}.sh /usr/local/sbin/
chmod +x /usr/local/sbin/yggdrasil-peers-{parse,update}.sh
cp yggdrasil-peers.{service,timer} /etc/systemd/system/
mkdir -p /var/lib/yggdrasil-peers

if [ -f /etc/default/yggdrasil-peers ]; then
    cp yggdrasil-peers /etc/default/yggdrasil-peers.new
else
    cp yggdrasil-peers /etc/default/
fi

systemctl daemon-reload
systemctl enable --now yggdrasil-peers.timer

