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
  MEMORY=4096
  VCPUS="$(nproc)"

  sudo usermod -a -G kvm,libvirt,libvirt-qemu "$USER"

  # Spin that virtualization
  sudo systemctl enable libvirtd
  sudo systemctl start libvirtd

  # Search is needed for $HOME so virt service can access the image file.
  chmod a+x "$HOME"

  sudo virt-install \
  --name breaker.com \
  --memory $MEMORY \
  --vcpus $VCPUS \
  --disk "$HOME/CentOS-7-x86_64-GenericCloud-2003.raw" \
  --os-variant rhel7 \
  --os-type linux \
  --import \
  --noautoconsole

  sleep 30
    for i in $(seq 0 29); do
    echo "loop $i"
      sleep 6s
      sudo virsh net-dhcp-leases default | tee dhcp-leases.txt

      ipaddy="$(grep breaker dhcp-leases.txt | awk '{print $5}' | cut -d'/' -f 1-1)"
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
  ssh -tt -o StrictHostKeyChecking=no "root@$IPADDR" "/root/openbeaker/$DOGFOOD $EXEC_TESTS"
}

travis_"$method"
