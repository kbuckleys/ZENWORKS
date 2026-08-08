#!/bin/sh

# ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
# ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
# └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
# https://github.com/kbuckleys/
# Remove corsair-headset-fix — mirror of setup.sh

set -e

# Stop and disable first, while the unit file is still in place.
# Tolerate it never having been enabled — 'set -e' would abort otherwise.
systemctl --user disable --now corsair-headset-fix.service 2>/dev/null || true
echo "  → service disabled & stopped"

# Only ever remove our own symlinks. If someone replaced one with a real file,
# it isn't ours to delete.
for link in "$HOME/.local/bin/corsair-headset-fix" \
            "$HOME/.config/systemd/user/corsair-headset-fix.service"; do
  if [ -L "$link" ]; then
    rm -f "$link"
    echo "  → removed $link"
  elif [ -e "$link" ]; then
    echo "  → skipped $link (not a symlink — left alone)" >&2
  fi
done

systemctl --user daemon-reload

# Remove the root-owned files. Skipped entirely when neither exists, so an
# already-clean system doesn't ask for a password.
RULE=/etc/udev/rules.d/99-corsair-headset-fix.rules
CONF=/etc/modprobe.d/99-corsair-headset-fix.conf

if [ -e "$RULE" ] || [ -e "$CONF" ]; then
  echo ""
  echo "Removing the system files needs root — sudo will ask for your password."
  sudo rm -f "$RULE" "$CONF"
  sudo udevadm control --reload
  echo "  → removed $RULE"
  echo "  → removed $CONF"
else
  echo "  → $RULE, $CONF (already absent)"
fi

echo ""
echo "Done. corsair-headset-fix is removed."
echo "Note: snd-usb-audio keeps the quirks until the module is reloaded, so the"
echo "      volume mapping and the silenced 'cannot get freq' error persist"
echo "      until you reboot."
