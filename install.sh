#!/usr/bin/env bash

cp yggdrasil-peers-{parse,update}.sh /usr/local/sbin/
chmod +x /usr/local/sbin/yggdrasil-peers-{parse,update}.sh
cp yggdrasil-peers.{service,timer} /etc/systemd/system/
cp yggdrasil-peers /etc/default/
mkdir -p /var/lib/yggdrasil-peers

systemctl daemon-reload
systemctl enable --now yggdrasil-peers.timer

