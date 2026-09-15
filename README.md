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
```quickshell``` ```qt6-declarative``` ```hyprland ttf-jetbrains-mono-nerd``` ```coreutils``` ```util-linux``` ```pciutils``` ```glib2``` ```systemd``` ```pam``` ```polkit``` ```libcap``` ```ripgrep``` ```fd``` ```bat``` ```imagemagick``` ```ffmpeg``` ```poppler``` ```libarchive``` ```7zip``` ```zip``` ```git``` ```udisks2``` ```wl-clipboard``` ```xdg-utils``` ```xdg-terminal-exec``` ```libnotify``` ```jq``` ```curl``` ```libpulse``` ```pamixer``` ```pipewire``` ```playerctl``` ```cliphist``` ```grim``` ```libqalculate``` ```rbw``` ```bandwhich``` ```qt6-imageformats``` ```kimageformats```

Notes
-
- Qt reads its image-format plugin list ONCE PER PROCESS. After installing ```qt6-imageformats``` or ```kimageformats``` you must restart quickshell; a config reload is not enough
- bandwhich needs a capability grant to read traffic without root: ```scripts/bandwhich-grant.sh``` does this via ```pkexec```
- ```xdg-open``` means the suite inherits whatever handlers your system has. Those are not listed here and cannot be enumerated from the code
- Remember to make the script files in ```/quickshell/scripts/``` executable
