#!/bin/sh
# Run directly as an X client (via `startx onetime-account-setup.sh`, as
# root - see firstboot.sh) after Ansible has provisioned the temporary
# "setup" bootstrap account. Raw console keyboard input turned out to be
# unreliable for this ISO's target environment, which is why this graphical
# rofi prompt collects the real account details instead of a text prompt at
# the rc.firsttime console.
#
# Renames the "setup" bootstrap account to whatever's entered here, then
# exits - which ends this X session and lets firstboot.sh finish up.
set -e

while true; do
	NEWUSER=$(rofi -dmenu -p "Username" -lines 0)
	[ -n "$NEWUSER" ] && break
done
FULLNAME=$(rofi -dmenu -p "Full name" -lines 0)
while true; do
	PASS1=$(rofi -dmenu -password -p "Password" -lines 0)
	PASS2=$(rofi -dmenu -password -p "Confirm password" -lines 0)
	[ -n "$PASS1" ] && [ "$PASS1" = "$PASS2" ] && break
	rofi -e "Passwords didn't match or were empty - try again."
done

HASH=$(printf '%s' "$PASS1" | encrypt)
usermod -l "$NEWUSER" -m -d "/home/$NEWUSER" -c "$FULLNAME" -p "$HASH" setup
# Replaces the temporary nopass-setup rule (that account no longer exists
# under that name) with a normal password-gated one for the real account.
echo "permit persist $NEWUSER" > /etc/doas.conf
