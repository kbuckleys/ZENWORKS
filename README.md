<picture>
  <source media="(prefers-color-scheme: dark)" srcset="https://github.com/user-attachments/assets/b5ce90c4-8ec2-489c-8f47-1fc84abc154b">
  <img src="image-light.png" alt="">
</picture>

<h3><p align="center">
A zen Arch-based ecosystem in Quickshell
</p></h3>

---

Dependencies
-
```quickshell``` ```qt6-declarative``` ```hyprland``` ```ttf-jetbrains-mono-nerd``` ```coreutils``` ```util-linux``` ```pciutils``` ```glib2``` ```systemd``` ```pam``` ```polkit``` ```libcap``` ```ripgrep``` ```fd``` ```bat``` ```imagemagick``` ```ffmpeg``` ```poppler``` ```libarchive``` ```7zip``` ```git``` ```udisks2``` ```wl-clipboard``` ```xdg-utils``` ```xdg-terminal-exec``` ```libnotify``` ```jq``` ```curl``` ```libpulse``` ```pipewire``` ```playerctl``` ```cliphist``` ```grim``` ```libqalculate``` ```rbw``` ```bandwhich``` ```qt6-imageformats``` ```qt6-multimedia``` ```qt6-multimedia-ffmpeg``` ```kimageformats``` ```attr``` ```rsync``` ```inotify-tools``` ```fzf``` ```python``` ```file``` ```wtype``` ```iproute2``` ```procps-ng``` ```bash``` ```ttf-dseg``` ```waybar-updates``` ```hyprshutdown``` ```solaar``` ```mpv``` ```ratarmount``` ```unrar``` ```pacman-contrib``` ```expac``` ```gawk``` ```sudo``` ```pinentry``` ```xdg-user-dirs``` ```unicode-emoji```

Optional: ```nvidia-utils``` (the GPU meter on NVIDIA cards)

The Hyprland config in ```.config/hypr``` also calls: ```kitty``` ```firefox``` ```btop``` ```wiremix``` ```pamixer``` ```hyprpicker``` ```slurp``` ```wf-recorder``` ```wl-clip-persist``` ```hyprpolkitagent``` ```xdg-desktop-portal-hyprland``` ```xdg-desktop-portal-termfilechooser```

Notes
-
- Qt reads its image-format plugin list ONCE PER PROCESS. After installing ```qt6-imageformats``` or ```kimageformats``` you must restart quickshell; a config reload is not enough
- bandwhich needs a capability grant to read traffic without root: ```scripts/bandwhich-grant.sh``` does this via ```pkexec```
- Ceres installs ```paru``` itself on first use if it is missing, so it is not listed above
- ```SUPER + M``` / ```SUPER + SHIFT + M``` in ```binds.lua``` run a personal project (```~/Projects/spoot```) that is not part of this repo
- ```xdg-open``` means the suite inherits whatever handlers your system has. Those are not listed here and cannot be enumerated from the code

Endpoints
-
| Component | Endpoint |
| --- | --- |
| App Launcher / Shell Command | qs ipc call Cynosure toggle |
| File Manager | qs ipc call Terminus spawn |
| Clipboard Manager | qs ipc call Folio toggle |
| Calculator | qs ipc call Metis toggle |
| Recursive Search | qs ipc call Artemis toggle |
| Emoji Search | qs ipc call Ideo emoji |
| Glyph Search | qs ipc call Ideo nerd |
| Bitwarden Vault | qs ipc call Calypso toggle |
| System Monitor | qs ipc call Zeus toggle |
| Dictionary | qs ipc call Lexi toggle |
| Translator | qs ipc call Lexi translate |
| Background Browser | qs ipc call Picasso toggle |
| Package Manager | qs ipc call Ceres toggleWindow packages |
| Package Manager - Updates | qs ipc call Ceres toggleWindow updates |
