#!/bin/sh
# ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
# ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
# └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
# https://github.com/kbuckleys/
#
# Zenworks' ZSH SETUP — the prompt, suggestions and fuzzy completion the
# shell ships in zsh/ beside it (/usr/share/zenworks/zsh), offered once at
# the first start and from oracle's Default apps (oracle/ZshSetup.qml).
# Never put in place unasked: a package does not change anyone's shell.
#
#   zsh-setup.sh check   "same" when ~/.zshrc and ~/.p10k.zsh are the shipped
#                        ones already, else "differs"; then "missing:" and
#                        the packages it needs that are not installed; then
#                        "login: yes" when zsh is your login shell, else "no"
#   zsh-setup.sh apply   yours kept as *.before-zenworks (never overwritten:
#                        a second one gets the time after it), the shipped
#                        ones copied in
#   zsh-setup.sh login   zsh made your login shell, unless it is already —
#                        through pkexec, so the polkit agent asks the password —
#                        and this session told so (SHELL, in hyprland and in
#                        systemd's user environment): what starts from now on
#                        gets zsh, with no logging out first (2026-10-25)

here=$(dirname "$(readlink -f "$0")")
shipped=$(readlink -f "$here/../../zsh")
set -- "${1:-}"

case $1 in
check)
	if cmp -s "$shipped/zshrc" "$HOME/.zshrc" && cmp -s "$shipped/p10k.zsh" "$HOME/.p10k.zsh"; then
		echo same
	else
		echo differs
	fi
	# what the shipped zshrc runs: zsh itself, git for zinit's first clone,
	# fzf and zoxide (each of these packages names its own command)
	missing=""
	for p in zsh git fzf zoxide; do
		command -v "$p" >/dev/null 2>&1 || missing="$missing $p"
	done
	echo "missing:$missing"
	z=$(command -v zsh 2>/dev/null)
	if [ -n "$z" ] && [ "$(getent passwd "$(id -un)" | cut -d: -f7)" = "$z" ]; then echo "login: yes"; else echo "login: no"; fi
	;;
apply)
	[ -f "$shipped/zshrc" ] && [ -f "$shipped/p10k.zsh" ] || { echo "no shipped zsh setup at $shipped" >&2; exit 1; }
	for pair in "zshrc .zshrc" "p10k.zsh .p10k.zsh"; do
		src="$shipped/${pair% *}"
		dst="$HOME/${pair#* }"
		if [ -e "$dst" ] && ! cmp -s "$src" "$dst"; then
			keep="$dst.before-zenworks"
			[ -e "$keep" ] && keep="$keep-$(date +%Y%m%d-%H%M%S)"
			mv -- "$dst" "$keep" || exit 1
		fi
		# a fresh file, readable by you: not cp, which carries a read-only
		# source's mode over and then cannot write over its own copy
		install -m 644 -- "$src" "$dst" || exit 1
	done
	;;
login)
	z=$(command -v zsh) || { echo "zsh is not installed" >&2; exit 1; }
	me=$(id -un)
	if [ "$(getent passwd "$me" | cut -d: -f7)" != "$z" ]; then
		grep -qx "$z" /etc/shells || { echo "$z is not in /etc/shells" >&2; exit 1; }
		pkexec chsh -s "$z" "$me" || exit $?
	fi
	# this session too: SHELL was read once, at login
	[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ] && hyprctl -q eval "hl.env(\"SHELL\", \"$z\")" >/dev/null 2>&1
	systemctl --user set-environment SHELL="$z" >/dev/null 2>&1
	exit 0
	;;
*)
	echo "usage: zsh-setup.sh check | apply | login" >&2
	exit 2
	;;
esac
