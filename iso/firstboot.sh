#!/bin/sh
# Runs once via /etc/rc.firsttime (as root, real networking up). Bootstraps
# Ansible and runs the playbook locally against the "mike" user account
# created during install.
#
# Tested end-to-end against a real fresh autoinstall (2026-08-25) - the
# only failure hit was a transient CDN download hiccup on one package
# ("Premature end of archive"), not a logic bug, hence the retry loop
# below rather than anything more elaborate.
set -e

REPO_URL_LAN="http://git.lan/mike/openbsd-btw.git"
REPO_URL_PUBLIC="https://gitlab.com/molszewski423/openbsd-btw.git"

retry_pkg_add() {
	tries=0
	until pkg_add -I "$@"; do
		tries=$((tries + 1))
		if [ "$tries" -ge 3 ]; then
			echo "openbsd-btw firstboot: pkg_add failed 3x, giving up on: $*"
			return 1
		fi
		echo "openbsd-btw firstboot: pkg_add failed (attempt $tries), retrying..."
		sleep 5
	done
}

echo "openbsd-btw firstboot: installing bootstrap deps"
retry_pkg_add git python3 py3-pip

echo "openbsd-btw firstboot: installing ansible"
pip3 install --break-system-packages ansible-core

echo "openbsd-btw firstboot: granting mike temporary passwordless doas for this run"
echo "permit nopass mike" >> /etc/doas.conf

echo "openbsd-btw firstboot: cloning repo and running playbook as mike"
# Prefer the LAN gitea instance (faster, and it's the source of truth), but
# that's only reachable on the home network - fall back to the public
# GitLab mirror so this works on any laptop with just internet access.
su -l mike -c "
	git clone '$REPO_URL_LAN' ~/openbsd-btw 2>/dev/null || git clone '$REPO_URL_PUBLIC' ~/openbsd-btw
	cd ~/openbsd-btw/ansible
	ansible-playbook site.yml -i 'localhost,' -c local
"

echo "openbsd-btw firstboot: revoking temporary passwordless doas"
sed -i '/^permit nopass mike$/d' /etc/doas.conf

echo "openbsd-btw firstboot: done"
