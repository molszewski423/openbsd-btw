#!/bin/sh
# Runs once via /etc/rc.firsttime (as root, real networking up). Bootstraps
# Ansible and runs the playbook locally against the "mike" user account
# created during install.
#
# NOTE: this hasn't been run end-to-end against a real fresh install yet
# (see repo README / plan notes) - treat it as a solid first draft that
# may need adjustment once actually tested.
set -e

echo "openbsd-btw firstboot: installing bootstrap deps"
pkg_add -I git python3 py3-pip

echo "openbsd-btw firstboot: installing ansible"
pip3 install --break-system-packages ansible-core

echo "openbsd-btw firstboot: granting mike temporary passwordless doas for this run"
echo "permit nopass mike" >> /etc/doas.conf

echo "openbsd-btw firstboot: cloning repo and running playbook as mike"
su -l mike -c '
	git clone http://git.lan/mike/openbsd-btw.git ~/openbsd-btw
	cd ~/openbsd-btw/ansible
	ansible-playbook site.yml -i "localhost," -c local
'

echo "openbsd-btw firstboot: revoking temporary passwordless doas"
sed -i '/^permit nopass mike$/d' /etc/doas.conf

echo "openbsd-btw firstboot: done"
