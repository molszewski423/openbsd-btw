#!/bin/sh
# Runs once via /etc/rc.firsttime (as root, real networking up). Bootstraps
# a temporary account, provisions the full desktop via Ansible, then hands
# off to a graphical (X11) prompt for the real account details - see
# onetime-account-setup.sh for why that runs there instead of here.
#
# The bootstrap/pkg_add/playbook-run mechanics were tested end-to-end
# against a real fresh autoinstall (2026-08-25) - the only failure hit was
# a transient CDN download hiccup on one package ("Premature end of
# archive"), not a logic bug, hence the retry loop below rather than
# anything more elaborate. That test used an interactive read/passwd
# prompt right here instead of the bootstrap-account/X11 handoff below -
# raw console keyboard input turned out to be unreliable for this ISO's
# target environment, which is why account creation moved to X11.
set -e

# rc.firsttime runs with a minimal base-system PATH that doesn't include
# /usr/local/bin, where package-installed binaries (ansible-playbook, etc.)
# actually live - hit this for real testing ("pip3: not found" right after
# py3-pip installed successfully, back when this used pip). /usr/X11R6/bin
# is needed too, for startx - hit "startx: not found" without it.
export PATH=/usr/local/bin:/usr/local/sbin:/usr/X11R6/bin:$PATH

REPO_URL="https://gitlab.com/molszewski423/openbsd-btw.git"
BOOTSTRAP_USER=setup

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

# autoinstall skipped user creation entirely (install.conf: "Setup a user =
# no") since it can't ask just this one question interactively. This
# temporary account exists only until onetime-account-setup.sh renames it
# to whatever the real user picks - no password is ever set for "setup"
# itself.
echo "openbsd-btw firstboot: creating temporary bootstrap account"
useradd -m -G wheel "$BOOTSTRAP_USER"
# nopass, not persist: "setup" has no password at all (see above), so it
# has nothing to authenticate a doas password prompt with.
echo "permit nopass $BOOTSTRAP_USER" >> /etc/doas.conf

echo "openbsd-btw firstboot: installing bootstrap deps and ansible"
# ansible-core installed via pip tries to build the cryptography package
# from source (needs Rust, and even then hits a maturin platform-detection
# bug: "Unsupported platform: 313") - real failure hit during testing.
# OpenBSD packages ansible natively; use that instead of fighting pip.
retry_pkg_add git python-3.13.14 ansible

echo "openbsd-btw firstboot: cloning repo and running playbook as $BOOTSTRAP_USER"
# Public GitLab mirror only - this ISO is meant to be downloadable and
# usable by anyone, not just on the home LAN.
su -l "$BOOTSTRAP_USER" -c "
	git clone '$REPO_URL' ~/openbsd-btw
	cd ~/openbsd-btw/ansible
	ansible-playbook site.yml -i 'localhost,' -c local -e ansible_user=$BOOTSTRAP_USER
"

echo "openbsd-btw firstboot: launching graphical account setup"
# Run directly as root (not via su to $BOOTSTRAP_USER): login(1) normally
# chowns the console/wsdisplay device nodes to whoever logs in, which is
# what actually gives a regular user permission to open the console driver
# - su doesn't do that, and hit exactly this as a real failure ("No
# console driver found") when this ran as $BOOTSTRAP_USER instead. Root
# always has that permission already.
startx /onetime-account-setup.sh || \
	echo "openbsd-btw firstboot: graphical account setup failed - $BOOTSTRAP_USER account left in place, check /var/log/Xorg.0.log"

echo "openbsd-btw firstboot: done"
