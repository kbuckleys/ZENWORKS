<p align="center">
  <img src="zenworks.png" alt="ZENWORKS" width="800">
</p>

<h3><p align="center">
A zen Arch-based ecosystem in Quickshell
</p></h3>

---

ZENWORKS is a desktop environment for Arch Linux, built on
[Quickshell](https://quickshell.org) and [Hyprland](https://hyprland.org).

## Install

ZENWORKS is on the AUR. With an AUR helper:

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

Log out and pick **ZENWORKS** on your login screen, or run `zenworks` from a
text console.

A login screen set up to run one fixed command (greetd with
`--cmd start-hyprland`, for instance) needs that command changed to
`zenworks`.

On the first start, ZENWORKS asks whether you want its terminal setup: zsh
with a fast prompt, suggestions and fuzzy completion. Your own setup is kept
as a backup. Oracle › Default apps › Terminal setup offers it again later.

## Your settings

Everything you change lives in `~/.config/zenworks`: your themes, monitors,
shortcuts, input, Plato's plugins, and your own kitty lines
(`~/.config/zenworks/kitty/custom.conf`). An update never touches it.

## Update

ZENWORKS updates like any other package: Ceres' Updates lists a new version
beside the rest (Oracle › About › Check for updates opens it), or run
`paru -Syu`.

## Remove

```sh
sudo pacman -Rns zenworks
```

Your settings stay in `~/.config/zenworks`; delete that directory too for a
clean slate.

## Working on ZENWORKS

To run a working copy instead of the installed ZENWORKS, put the path of
its `config` directory in `~/.config/zenworks/dev`, one line:

```sh
mkdir -p ~/.config/zenworks
echo ~/Projects/ZENWORKS/config > ~/.config/zenworks/dev
zenworks --where
```

Log in again and that copy runs, with Quickshell's live reload. Remove the
file to go back to the installed one.

## Credits

ZENWORKS stands on [Quickshell](https://quickshell.org) and
[Hyprland](https://hyprland.org), and on Qt, PipeWire and the many tools it
brings along.

## License

GPL-3.0-or-later. See [LICENSE](LICENSE).

