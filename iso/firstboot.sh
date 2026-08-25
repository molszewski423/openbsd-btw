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

# rc.firsttime runs with a minimal base-system PATH that doesn't include
# /usr/local/bin, where package-installed binaries (ansible-playbook, etc.)
# actually live - hit this for real testing ("pip3: not found" right after
# py3-pip installed successfully, back when this used pip).
export PATH=/usr/local/bin:/usr/local/sbin:$PATH

REPO_URL="https://gitlab.com/molszewski423/openbsd-btw.git"

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

echo "openbsd-btw firstboot: installing bootstrap deps and ansible"
# ansible-core installed via pip tries to build the cryptography package
# from source (needs Rust, and even then hits a maturin platform-detection
# bug: "Unsupported platform: 313") - real failure hit during testing.
# OpenBSD packages ansible natively; use that instead of fighting pip.
retry_pkg_add git python-3.13.14 ansible

echo "openbsd-btw firstboot: granting mike temporary passwordless doas for this run"
echo "permit nopass mike" >> /etc/doas.conf

echo "openbsd-btw firstboot: cloning repo and running playbook as mike"
# Public GitLab mirror only - this ISO is meant to be downloadable and
# usable by anyone, not just on the home LAN.
su -l mike -c "
	git clone '$REPO_URL' ~/openbsd-btw
	cd ~/openbsd-btw/ansible
	ansible-playbook site.yml -i 'localhost,' -c local
"

echo "openbsd-btw firstboot: revoking temporary passwordless doas"
sed -i '/^permit nopass mike$/d' /etc/doas.conf

echo "openbsd-btw firstboot: done"
