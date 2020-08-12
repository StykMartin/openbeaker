#!/bin/bash

set -ev

method=$1

function travis_before_install()
{
	echo "Verify that virtualization is available ..."
	kvm-ok
	echo "Verify that virtualization is available ...  done"
}

function travis_install()
{
  REVISION="2003"
  IMAGE_BASE_NAME="CentOS-7-x86_64-GenericCloud-$REVISION.raw"
  TAR_BASE_NAME="$IMAGE_BASE_NAME.tar.gz"
  IMAGE_URL="https://cloud.centos.org/centos/7/images/$TAR_BASE_NAME"
  SUM_URL="https://cloud.centos.org/centos/7/images/sha256sum.txt"
  MEMORY=4096
  VCPUS="$(nproc)"

  sudo usermod -a -G kvm,libvirt,libvirt-qemu "$USER"

  # Spin that virtualization
  sudo systemctl enable libvirtd
  sudo systemctl start libvirtd

  # SSH Keys
  ssh-keygen -N "" -f "$HOME/.ssh/id_rsa"

  cd "$HOME"
  wget "$IMAGE_URL"
  wget "$SUM_URL"

  # Verify
  sha256sum --ignore-missing -c ./sha256sum.txt

  # Unpack
  tar -xvf $TAR_BASE_NAME

  # Search is needed for $HOME so virt service can access the image file.
  chmod a+x "$HOME"

  sudo virt-sysprep -a "$IMAGE_BASE_NAME" \
  --root-password password:123456 \
  --hostname centosvm \
  --mkdir /root/.ssh \
  --upload "$HOME/.ssh/id_rsa.pub:/root/.ssh/authorized_keys" \
  --chmod '0600:/root/.ssh/authorized_keys' \
  --run-command 'chown root:root /root/.ssh/authorized_keys' \
  --copy-in "$TRAVIS_BUILD_DIR:/root" \
  --network \
  --selinux-relabel

  sudo virt-install \
  --name centosvm \
  --memory $MEMORY \
  --vcpus $VCPUS \
  --disk "$IMAGE_BASE_NAME" \
  --os-variant rhel7 \
  --os-type linux \
  --import \
  --noautoconsole

  sleep 30
    for i in $(seq 0 29); do
    echo "loop $i"
      sleep 6s
      sudo virsh net-dhcp-leases default | tee dhcp-leases.txt

      ipaddy="$(grep centosvm dhcp-leases.txt | awk '{print $5}' | cut -d'/' -f 1-1)"
      if [ -n "$ipaddy" ]; then
          echo "ipaddy: $ipaddy"
          break
    fi
  done

  if [ -z "$ipaddy" ]; then
      echo "ipaddy zero length, exiting with error 1"
      exit 1
  fi

  echo $ipaddy > $HOME/vm-ip

}

function travis_script()
{
  DOGFOOD="Misc/travis-dogfood.sh"
  IPADDR="$(head -n 1 $HOME/vm-ip)"
  ssh -v -tt -o StrictHostKeyChecking=no "root@$IPADDR" "/root/openbeaker/$DOGFOOD"
}

travis_"$method"
