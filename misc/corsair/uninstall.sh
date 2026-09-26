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

# Noted before the loop removes it: whether the WirePlumber rules are ours and
# live, which decides whether the audio stack needs a restart below.
WP="$HOME/.config/wireplumber/wireplumber.conf.d/51-corsair-headset-fix.conf"
WP_LINKED=0
[ -L "$WP" ] && WP_LINKED=1

# Only ever remove our own symlinks. If someone replaced one with a real file,
# it isn't ours to delete.
for link in "$HOME/.local/bin/corsair-headset-fix" \
            "$HOME/.config/systemd/user/corsair-headset-fix.service" \
            "$WP"; do
  if [ -L "$link" ]; then
    rm -f "$link"
    echo "  → removed $link"
  elif [ -e "$link" ]; then
    echo "  → skipped $link (not a symlink — left alone)" >&2
  fi
done

systemctl --user daemon-reload

# WirePlumber read the node rules when it started and keeps them until it
# restarts, so removing the link alone changes nothing yet. Only restart when
# the link was actually ours and is now gone — a brief audio dropout.
if [ "$WP_LINKED" = 1 ]; then
  systemctl --user restart wireplumber pipewire pipewire-pulse 2>/dev/null || true
  echo "  → audio stack restarted (WirePlumber rules dropped)"
fi

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
