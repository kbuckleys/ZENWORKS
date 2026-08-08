#!/bin/sh

# ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
# ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
# └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
# https://github.com/kbuckleys/
# Deploy corsair-headset-fix — one-command setup

set -e

DIR="$(cd "$(dirname "$0")" && pwd)"

# Fail loudly here rather than letting corsair-headset-fix exit 0 silently on
# every login: without pactl it can't resolve the card and just gives up.
MISSING=""
for c in pactl amixer; do
  command -v "$c" >/dev/null 2>&1 || MISSING="$MISSING $c"
done
if [ -n "$MISSING" ]; then
  echo "Missing required command(s):$MISSING" >&2
  echo "  pactl → libpulse    amixer → alsa-utils" >&2
  exit 1
fi

# Symlink to ~/.local/bin (for manual invocation)
mkdir -p "$HOME/.local/bin"
ln -sf "$DIR/corsair-headset-fix" "$HOME/.local/bin/corsair-headset-fix"
echo "  → ~/.local/bin/corsair-headset-fix"

# Symlink to systemd user units
mkdir -p "$HOME/.config/systemd/user"
ln -sf "$DIR/corsair-headset-fix.service" "$HOME/.config/systemd/user/corsair-headset-fix.service"
echo "  → ~/.config/systemd/user/corsair-headset-fix.service"

# Enable and start the service
systemctl --user daemon-reload
systemctl --user enable --now corsair-headset-fix.service
echo "  → service enabled & started"

# Install the udev rule (re-applies the fix on replug) and the modprobe.d
# quirks (silences the kernel's 'cannot get freq' error, fixes the volume
# curve). Both need root; both are skipped when already up to date, so
# re-running this doesn't ask for a password.
RULE=/etc/udev/rules.d/99-corsair-headset-fix.rules
CONF=/etc/modprobe.d/99-corsair-headset-fix.conf

if ! cmp -s "$DIR/99-corsair-headset-fix.rules" "$RULE" ||
   ! cmp -s "$DIR/99-corsair-headset-fix.conf" "$CONF"; then
  echo ""
  echo "Installing the system files needs root — sudo will ask for your password."
fi

if cmp -s "$DIR/99-corsair-headset-fix.rules" "$RULE"; then
  echo "  → $RULE (already up to date)"
else
  sudo install -Dm0644 "$DIR/99-corsair-headset-fix.rules" "$RULE"
  sudo udevadm control --reload
  echo "  → $RULE"
fi

# snd-usb-audio only reads this when it loads, so a reboot (or a module
# reload with the card released) is needed before it takes effect.
if cmp -s "$DIR/99-corsair-headset-fix.conf" "$CONF"; then
  echo "  → $CONF (already up to date)"
else
  sudo install -Dm0644 "$DIR/99-corsair-headset-fix.conf" "$CONF"
  echo "  → $CONF (takes effect on next reboot)"
fi

echo ""
echo "Done. corsair-headset-fix is now active."
