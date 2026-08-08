#!/bin/sh

# ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
# ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
# └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
# https://github.com/kbuckleys/
# Deploy corsair-headset-fix — one-command setup

set -e

DIR="$(cd "$(dirname "$0")" && pwd)"

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

# Install the udev rule so the fix re-applies on replug (needs root).
# Skipped when already up to date, so re-running this doesn't ask for a password.
RULE=/etc/udev/rules.d/99-corsair-headset-fix.rules
if cmp -s "$DIR/99-corsair-headset-fix.rules" "$RULE"; then
  echo "  → $RULE (already up to date)"
else
  echo ""
  echo "Installing the udev rule needs root — sudo will ask for your password."
  sudo install -Dm0644 "$DIR/99-corsair-headset-fix.rules" "$RULE"
  sudo udevadm control --reload
  echo "  → $RULE"
fi

echo ""
echo "Done. corsair-headset-fix is now active."
