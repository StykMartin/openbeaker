#!/bin/bash

set -eux

method=$1

function travis_before_install
{
	echo "Verify that virtualization is available ..."
	kvm-ok || true
	grep 'vmx\|kvm' /proc/cpuinfo || true
	ls -l /dev/kvm || true
	grep -r kvm /lib/udev/rules.d
	echo "Verify that virtualization is available ...  done"
}

travis_"$method"
