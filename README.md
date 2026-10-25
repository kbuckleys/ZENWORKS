<p align="center">
  <img src="zenworks.png" alt="Zenworks" width="800">
</p>

<h3><p align="center">
A zen Arch-based ecosystem in Quickshell
</p></h3>

---

Zenworks is a desktop environment for Arch Linux, built on
[Quickshell](https://quickshell.org) and [Hyprland](https://hyprland.org).

## Install

Zenworks is on the AUR. With an AUR helper:

```sh
paru -S zenworks
```

Everything it needs comes with it: Hyprland, Quickshell, the portals, the
fonts and the tools the suite uses. A few extras are optional; they are
listed when the install finishes, and most are installed for you the first
time you use what needs them.

On NVIDIA, also install your driver (`nvidia-open` or `nvidia`, with
`nvidia-utils`).

## Start

Log out and pick **Zenworks** on your login screen, or run `zen` from a
text console. (`zenworks`, its older name, still works.)

A login screen set up to run one fixed command (greetd with
`--cmd start-hyprland`, for instance) needs that command changed to `zen`.

The very first start opens the shortcuts cheat sheet; **Super + /** brings
it back any time, and typing filters it. A moment later Zenworks asks
whether you want its terminal setup: zsh with a fast prompt, suggestions
and fuzzy completion. Your own setup is kept as a backup. Oracle › Default
apps › Terminal setup offers it again later.

## Getting around

| Keys | What they do |
| --- | --- |
| Super + Space | Cynosure, the launcher |
| Super + / | Every shortcut on one sheet |
| Super + Tab | The window switcher: hold Super, tap Tab to step, let go to switch (Shift goes back) |
| Super + Ctrl + Tab | The same, for the windows of the app in front |
| Super + 1 … 5 | Go to a workspace; a strip of your workspaces shows as you switch |
| Super + Return | The terminal |
| Super + E | Terminus, the file manager |
| Super + Q | Close the window |
| Super + Escape | Lock the screen |

Every shortcut can be changed in Oracle › Shortcuts. The workspace strip
can be turned off in Oracle › Windows.

## Your settings

Everything you change lives in `~/.config/zenworks`: your themes, monitors,
shortcuts, input, Plato's plugins, and your own kitty lines
(`~/.config/zenworks/kitty/custom.conf`). An update never touches it.

To start over, log out and run `zen --reset` from a text console: your
settings are moved to `~/zenworks-reset-<date>`, never deleted, and the
next start is a first start again.

## Update

Zenworks updates like any other package: Ceres' Updates lists a new version
beside the rest (Oracle › About › Check for updates opens it), or run
`paru -Syu`.

## Remove

```sh
sudo pacman -Rns zenworks
```

Your settings stay in `~/.config/zenworks`; delete that directory too for a
clean slate.

## Working on Zenworks

To run a working copy instead of the installed Zenworks, put the path of
its `config` directory in `~/.config/zenworks/dev`, one line:

```sh
mkdir -p ~/.config/zenworks
echo ~/Projects/Zenworks/config > ~/.config/zenworks/dev
zen --where
```

Log in again and that copy runs, with Quickshell's live reload. Remove the
file to go back to the installed one.

## Credits

Zenworks stands on [Quickshell](https://quickshell.org) and
[Hyprland](https://hyprland.org), and on Qt, PipeWire and the many tools it
brings along.

## License

GPL-3.0-or-later. See [LICENSE](LICENSE).

