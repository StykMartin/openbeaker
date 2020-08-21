#!/bin/bash

set -ex

REVISION="2003"
IMAGE_BASE_NAME="CentOS-7-x86_64-GenericCloud-$REVISION.raw"
TAR_BASE_NAME="$IMAGE_BASE_NAME.tar.gz"
IMAGE_URL="https://cloud.centos.org/centos/7/images/$TAR_BASE_NAME"
SUM_URL="https://cloud.centos.org/centos/7/images/sha256sum.txt"
CACHED_SSH_KEY=false

cd "$HOME" || exit
chmod a+x "$HOME"
wget "$SUM_URL"

SSH_KEY=$HOME/.ssh/id_rsa
if [ ! -f "$SSH_KEY" ]; then
  ssh-keygen -N "" -f "$HOME/.ssh/id_rsa"
else
  ls -la $HOME/.ssh
  CACHED_SSH_KEY=true
fi


if [ $CACHED_SSH_KEY = false ] || [ ! -f "$HOME/$IMAGE_BASE_NAME" ]; then
  wget "$IMAGE_URL"
  sha256sum --ignore-missing -c ./sha256sum.txt
  tar -xvf $TAR_BASE_NAME
  sudo virt-sysprep -a "$IMAGE_BASE_NAME" \
  --root-password password:123456 \
  --hostname breaker.com \
  --mkdir /root/.ssh \
  --upload "$HOME/.ssh/id_rsa.pub:/root/.ssh/authorized_keys" \
  --chmod '0600:/root/.ssh/authorized_keys' \
  --run-command 'chown root:root /root/.ssh/authorized_keys' \
  --network \
  --selinux-relabel
fi