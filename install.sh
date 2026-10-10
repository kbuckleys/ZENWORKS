#!/usr/bin/env bash
# ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
# ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
# └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
# https://github.com/kbuckleys/
#
# ZENWORKS installer, for Arch. Run it from a clone of this repo as your normal
# user (it asks for sudo when it needs it):  ./install.sh
#
#   1. paru or paru-git, built from the AUR
#   2. etc/pacman.conf put in place (all six repos, testing included), then a full sync
#   3. every package the suite needs
#   4. configs to $XDG_CONFIG_HOME and dotfiles to ~. Anything already there is
#      moved to <name>.bak-<timestamp> first; nothing is overwritten. The
#      .desktop entries for plato, picasso and terminus are not shipped: the
#      shell writes them on first start, with this machine's paths.
#   5. zsh as the login shell

set -euo pipefail

REPO="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}"
STAMP="$(date +%Y%m%d-%H%M%S)"

CONFIGS=(
  fastfetch hypr kitty quickshell xdg-desktop-portal xdg-desktop-portal-termfilechooser
)
DOTFILES=(.zshrc .p10k.zsh)

PACKAGES=(
  # compositor & session
  hyprland hyprshutdown hyprpolkitagent xcursor-pro-hyprcursor
  xdg-desktop-portal-hyprland xdg-desktop-portal-gtk xdg-desktop-portal-termfilechooser
  xdg-utils xdg-terminal-exec
  # shell (quickshell & qt)
  quickshell qt6-declarative qt6-imageformats qt6-multimedia qt6-multimedia-ffmpeg
  kimageformats libqalculate rbw
  # audio & media
  pipewire pipewire-pulse wireplumber libpulse alsa-utils pamixer playerctl
  gst-plugins-good gst-plugins-bad gst-plugins-ugly
  ffmpeg mpv imagemagick perl-image-exiftool poppler ghostscript djvulibre
  tesseract tesseract-data-eng
  # wayland utilities
  wl-clipboard wl-clip-persist cliphist grim slurp wf-recorder wtype libnotify
  # files, archives & mounts
  fd fzf ripgrep bat jq file attr inotify-tools rsync
  7zip zip unzip unrar libarchive ratarmount fuse3 ntfs-3g ntfsprogs udisks2
  exfatprogs dosfstools btrfs-progs xfsprogs f2fs-tools
  # terminal & shell
  kitty zsh zoxide neovim git curl fastfetch stow
  # system & packages
  pacman-contrib expac gawk bandwhich iotop solaar glib2 gtk3 nodejs
  # fonts
  noto-fonts noto-fonts-cjk noto-fonts-extra noto-fonts-emoji
  ttf-jetbrains-mono-nerd ttf-dseg unicode-emoji
  otf-san-francisco otf-san-francisco-mono
)

# ── output ──────────────────────────────────────────────────────────────────
CYAN=$'\e[1;38;2;155;191;191m'   # zenon cyan, #9bbfbf
DIM=$'\e[38;2;80;96;96m'
RED=$'\e[1;31m'
RESET=$'\e[0m'

say()  { printf '%s::%s %s\n' "$CYAN" "$RESET" "$*"; }
note() { printf '%s   %s%s\n' "$DIM" "$*" "$RESET"; }
die()  { printf '%s:: %s%s\n' "$RED" "$*" "$RESET" >&2; exit 1; }

banner() {
  printf '\n%s' "$CYAN"
  cat <<'EOF'
   ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
   ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
   └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
EOF
  printf '%s\n' "$RESET"
}

# Move whatever is at $1 aside, so the install never destroys anything.
backup() {
  if [[ -e "$1" || -L "$1" ]]; then
    mv -- "$1" "$1.bak-$STAMP"
    note "kept the old one as $(basename -- "$1").bak-$STAMP"
  fi
}

# ── checks ──────────────────────────────────────────────────────────────────
preflight() {
  [[ $EUID -ne 0 ]] || die "run this as your normal user, not root; it asks for sudo itself"
  [[ -f /etc/arch-release ]] || die "this installer is for Arch Linux"
  command -v sudo >/dev/null || die "sudo is needed"
  for d in "${CONFIGS[@]}"; do
    [[ -d "$REPO/config/$d" ]] || die "missing config/$d; run this from the ZENWORKS repo"
  done
  sudo -v
}

# ── 1. paru ─────────────────────────────────────────────────────────────────
install_paru() {
  if command -v paru >/dev/null; then
    say "paru is already installed ($(pacman -Qqo "$(command -v paru)"))"
    return
  fi

  local choice pkg
  say "Which paru?"
  note "1) paru      (latest release; the stable choice)"
  note "2) paru-git  (latest commit)"
  while :; do
    read -rp "   [1/2] " choice
    case "$choice" in
      1|"") pkg=paru; break ;;
      2)    pkg=paru-git; break ;;
      *)    note "enter 1 or 2" ;;
    esac
  done

  say "Building $pkg"
  sudo pacman -S --needed --noconfirm base-devel git
  local build
  build="$(mktemp -d)"
  git clone --depth 1 "https://aur.archlinux.org/$pkg.git" "$build/$pkg"
  (cd "$build/$pkg" && makepkg -si --noconfirm)
  rm -rf -- "$build"
}

# ── 2. pacman.conf + sync ──────────────────────────────────────────────────
install_pacman_conf() {
  say "Installing pacman.conf (core, extra and multilib, plus their -testing repos)"
  if ! cmp -s "$REPO/etc/pacman.conf" /etc/pacman.conf; then
    sudo cp -- /etc/pacman.conf "/etc/pacman.conf.bak-$STAMP"
    note "kept the old one as /etc/pacman.conf.bak-$STAMP"
    sudo install -m 644 -- "$REPO/etc/pacman.conf" /etc/pacman.conf
  fi
  say "Syncing repositories"
  sudo pacman -Syu --noconfirm
}

# ── 3. packages ─────────────────────────────────────────────────────────────
install_packages() {
  say "Installing packages"
  paru -S --needed "${PACKAGES[@]}"
}

# ── 4. files ────────────────────────────────────────────────────────────────
install_files() {
  say "Installing configs to $CONFIG"
  mkdir -p -- "$CONFIG"
  for d in "${CONFIGS[@]}"; do
    backup "$CONFIG/$d"
    cp -a -- "$REPO/config/$d" "$CONFIG/$d"
    note "$d"
  done

  # The portal does not expand ~ or $HOME in cmd=, so write the real path.
  sed -i "s|@CONFIG@|$CONFIG|g" "$CONFIG/xdg-desktop-portal-termfilechooser/config"
  # A repo uploaded through the GitHub web page loses its executable bits, so
  # set them again: the scripts, and the launchers the .desktop entries run.
  find "$CONFIG/quickshell" "$CONFIG/hypr" "$CONFIG/xdg-desktop-portal-termfilechooser" \
    -type f \( -name '*.sh' -o -name '*.py' -o -path '*/bin/*' \) -exec chmod +x {} +

  say "Installing dotfiles to $HOME"
  for f in "${DOTFILES[@]}"; do
    backup "$HOME/$f"
    cp -a -- "$REPO/home/$f" "$HOME/$f"
    note "$f"
  done
}

# ── 5. finishing touches ────────────────────────────────────────────────────
finish() {
  if [[ "$(getent passwd "$USER" | cut -d: -f7)" != "$(command -v zsh)" ]]; then
    say "Setting zsh as your login shell"
    chsh -s "$(command -v zsh)" || note "chsh failed; run: chsh -s $(command -v zsh)"
  fi

  systemctl --user daemon-reload 2>/dev/null || true

  printf '\n'
  say "ZENWORKS is installed."
  note "Log out and choose Hyprland at login, or run 'start-hyprland' from a TTY."
  note "Monitors: every screen starts at its preferred mode. Right-click the desktop,"
  note "  then Display settings, to set resolution, refresh, scale and rotation."
  note "Browser: SUPER+B opens your default browser (xdg-settings set default-web-browser <name>.desktop)."
  note "On NVIDIA, also install your driver (nvidia-open or nvidia) and nvidia-utils."
  printf '\n'
}

banner
preflight
install_paru
install_pacman_conf
install_packages
install_files
finish
