#!/usr/bin/env python3
# ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
# ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
# └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
# https://github.com/kbuckleys/
#
# THE PROGRAMS TABLE'S SOURCE — morpheus/icons.js' APPS is this script's
# output. To add a program, add its line below and run:
#
#     scripts/glyph-apps.py <glyphnames.json> [font file]
#
# glyphnames.json is nerd-fonts' own (github.com/ryanoasis/nerd-fonts, at the
# installed font's version). Every glyph is looked up by name and checked
# against the font's charset; a missing name, a glyph the font lacks or a
# name listed twice fails the run instead of writing a blank into the table.
# Paste the output between `const APPS = {` and `};`.

import json, subprocess, sys

names = json.load(open(sys.argv[1])); names.pop("METADATA", None)
# Default to wherever fontconfig finds the Nerd Font, not one distro's path.
font = sys.argv[2] if len(sys.argv) > 2 else subprocess.run(
    ["fc-match", "-f", "%{file}", "JetBrainsMono Nerd Font"],
    capture_output=True, text=True, check=True).stdout.strip()
charset = subprocess.run(["fc-query", "--format=%{charset}", font],
                         capture_output=True, text=True, check=True).stdout

# The font's own coverage, so a glyph it does not carry never enters the table.
have = set()
for part in charset.split():
    a, _, b = part.partition("-")
    lo = int(a, 16); hi = int(b, 16) if b else lo
    have.update(range(lo, hi + 1))

# program → glyph name. One line per program; `|` separates the names it is
# known by (package, command, desktop id), the first being the canonical one.
PROGRAMS = """
# ── browsers ──
firefox|firefox-developer-edition|firefox-nightly = fa-firefox
google-chrome|google-chrome-stable|chrome = md-google_chrome
microsoft-edge|microsoft-edge-stable|msedge = md-microsoft_edge
opera = dev-opera
safari = dev-safari
tor-browser|torbrowser-launcher|tor = linux-tor
# ── chat and social ──
discord|discord-canary|discord-ptb|vesktop|webcord|equibop|diskord = fa-discord
slack|slack-desktop = dev-slack
telegram|telegram-desktop|org.telegram.desktop|ayugram-desktop = fa-telegram
whatsapp|whatsapp-for-linux|whatsie|zapzap = fa-whatsapp
skype|skypeforlinux = md-skype
teams|teams-for-linux|microsoft-teams = md-microsoft_teams
mattermost|mattermost-desktop = dev-mattermost
teamspeak|teamspeak3|ts3client = fa-teamspeak
viber = fa-viber
wechat|wechat-uos = fa-wechat
keybase|keybase-gui = fa-keybase
mastodon = md-mastodon
reddit = fa-reddit
twitch = fa-twitch
youtube|freetube = fa-youtube
thunderbird|thunderbird-beta = linux-thunderbird
# ── media ──
spotify|spotify-launcher|spotify-player|spotifyd|spotify-qt|spoot|ncspot = fa-spotify
mpv|celluloid = linux-mpv
vlc = md-vlc
kodi = md-kodi
plex|plex-media-player|plexamp = md-plex
emby|emby-theater = md-emby
soundcloud = fa-soundcloud
kdenlive = linux-kdenlive
ffmpeg|ffplay|ffprobe = linux-ffmpeg
# ── graphics and making things ──
gimp = linux-gimp
inkscape = linux-inkscape
krita = linux-krita
blender = dev-blender
freecad = linux-freecad
openscad = linux-openscad
kicad = linux-kicad
prusa-slicer|prusaslicer = linux-prusaslicer
figma|figma-linux = dev-figma
godot|godot4 = dev-godot
unity|unityhub = dev-unity
unrealeditor|unrealengine = dev-unrealengine
processing = dev-processing
renpy = dev-renpy
arduino|arduino-ide = linux-arduino
octoprint = linux-octoprint
typst = linux-typst
latex|pdflatex|xelatex|lualatex|texstudio = dev-latex
# ── office and notes ──
libreoffice|soffice|libreoffice-fresh|libreoffice-still = linux-libreoffice
libreoffice-writer|lowriter = linux-libreofficewriter
libreoffice-calc|localc = linux-libreofficecalc
libreoffice-impress|loimpress = linux-libreofficeimpress
libreoffice-draw|lodraw = linux-libreofficedraw
libreoffice-math|lomath = linux-libreofficemath
libreoffice-base|lobase = linux-libreofficebase
obsidian = custom-obsidian
notion|notion-app|notion-app-electron = dev-notion
evernote = md-evernote
trello = dev-trello
jira = dev-jira
confluence = dev-confluence
# ── games ──
steam|steam-native|steam-runtime = fa-square_steam
minecraft|minecraft-launcher = md-minecraft
itch|itch-setup = fa-itch_io
# ── files and system ──
dolphin = md-dolphin
wireshark|tshark = custom-wireshark
teamviewer = md-teamviewer
lastpass = md-lastpass
dropbox = fa-dropbox
filezilla = dev-filezilla
putty = dev-putty
ssh|sshd = dev-ssh
monero|monero-wallet-gui|monerod = fa-monero
home-assistant|hass = md-home_assistant
wireguard|wg|wg-quick = linux-wireguard
docker|docker-compose|dockerd|lazydocker = linux-docker
podman|podman-compose = dev-podman
portainer = dev-portainer
kubectl|kubernetes|k9s|minikube = dev-kubernetes
k3s = dev-k3s
helm = dev-helm
vagrant = dev-vagrant
terraform|tofu = seti-terraform
packer = dev-packer
nomad = dev-nomad
consul = dev-consul
vault = dev-vault
pulumi = dev-pulumi
ansible|ansible-playbook = dev-ansible
nginx = dev-nginx
apache|httpd|apachectl = dev-apache
tomcat = dev-tomcat
prometheus = dev-prometheus
grafana|grafana-server = dev-grafana
kibana = dev-kibana
elasticsearch = dev-elasticsearch
jenkins = dev-jenkins
ngrok = dev-ngrok
pm2 = dev-pm2
uwsgi = dev-uwsgi
proxmox = dev-proxmox
heroku = dev-heroku
nix|nix-shell|nix-env = md-nix
homebrew|brew = dev-homebrew
# ── window managers and desktops ──
hyprland|hyprctl = linux-hyprland
sway|swaymsg = linux-sway
river = linux-river
i3|i3-msg = linux-i3
bspwm|bspc = linux-bspwm
dwm = linux-dwm
qtile = linux-qtile
xmonad = linux-xmonad
awesome = linux-awesome
fluxbox = linux-fluxbox
jwm = linux-jwm
enlightenment = linux-enlightenment
cinnamon = linux-cinnamon
# ── editors and IDEs ──
neovim|nvim|neovide = custom-neovim
vim|gvim|vi = custom-vim
emacs|emacsclient = dev-emacs
nano = dev-nano
vscode|code|visual-studio-code|visual-studio-code-bin|code-oss = cod-vscode
vscodium|codium = linux-vscodium
sublime-text|subl|sublime_text = dev-sublime
atom = dev-atom
intellij-idea|idea|intellij-idea-community-edition|intellij-idea-ultimate-edition = dev-intellij
clion = dev-clion
goland = dev-goland
pycharm|pycharm-community-edition|pycharm-professional = dev-pycharm
phpstorm = dev-phpstorm
rider = dev-rider
rubymine = dev-rubymine
webstorm = dev-webstorm
datagrip = dev-datagrip
dataspell = dev-dataspell
jetbrains-toolbox = dev-jetbrains
android-studio = dev-androidstudio
eclipse = dev-eclipse
netbeans = dev-netbeans
rstudio|rstudio-desktop = dev-rstudio
spyder = dev-spyder
jupyter|jupyter-lab|jupyter-notebook|jupyterlab = dev-jupyter
xcode = dev-xcode
qtcreator = linux-qt
# ── developer tools ──
git = md-git
gh|github-cli|github-desktop = dev-github
glab|gitlab = dev-gitlab
gitea = linux-gitea
forgejo = linux-forgejo
gitkraken = dev-gitkraken
sourcetree = dev-sourcetree
svn|subversion = dev-subversion
hg|mercurial = dev-mercurial
postman = dev-postman
insomnia = dev-insomnia
dbeaver = dev-dbeaver
sqldeveloper = dev-sqldeveloper
tmux = cod-terminal_tmux
bash = dev-bash
zsh = dev-zsh
awk|gawk = dev-awk
powershell|pwsh = dev-powershell
cmake = dev-cmake
gcc|g++ = dev-gcc
clang|llvm|clang++ = dev-llvm
bazel = dev-bazel
gradle = seti-gradle
maven|mvn = dev-maven
npm|npx = dev-npm
pnpm = dev-pnpm
yarn = dev-yarn
bun|bunx = dev-bun
eslint = dev-eslint
prettier = custom-prettier
vite = dev-vitejs
playwright = dev-playwright
composer = dev-composer
anaconda|conda = dev-anaconda
spack = dev-spack
hugo = dev-hugo
# ── languages ──
python|python3|ipython = dev-python
node|nodejs = dev-nodejs
deno = dev-denojs
ruby|irb|gem = fae-ruby_o
rust|cargo|rustc|rustup = dev-rust
go = md-language_go
java|javac = seti-java
kotlin|kotlinc = dev-kotlin
scala = dev-scala
lua|luajit = dev-lua
perl = dev-perl
php = dev-php
julia = dev-julia
r|rscript = dev-r
dart = dev-dart
flutter = dev-flutter
zig = dev-zig
nim = dev-nim
crystal = dev-crystal
elixir|iex|mix = custom-elixir
erlang|erl = dev-erlang
ocaml = dev-ocaml
haskell|ghc|ghci|cabal|stack = dev-haskell
racket = dev-racket
gleam = dev-gleam
swift = dev-swift
dotnet = dev-dotnet
matlab = dev-matlab
stata = dev-stata
# ── databases ──
mysql = dev-mysql
mariadb = dev-mariadb
postgresql|psql|postgres = dev-postgresql
sqlite|sqlite3 = dev-sqlite
redis|redis-server|redis-cli|valkey = dev-redis
mongodb|mongo|mongod|mongosh = dev-mongodb
couchdb = dev-couchdb
cassandra = dev-cassandra
clickhouse = dev-clickhouse
duckdb = dev-duckdb
surrealdb|surreal = dev-surrealdb
influxdb|influx = dev-influxdb
memcached = dev-memcached
rabbitmq|rabbitmq-server = dev-rabbitmq
neo4j = dev-neo4j
# ── the folder table's programs, in the glyph it already gives them ──
fish = fa-fish
foot|footclient = md-foot_print
zen-browser|zen = md-circle_double
wine|winecfg|wine64 = fa-wine_bottle
spicetify = fa-spotify
cliphist = fa-clipboard_list
nextcloud|nextcloud-client = fa-cloud
electron = md-electron_framework
# ── this shell's own ──
ceres|paru|yay|pacman|makepkg = md-arch
"""

def esc(cp):
    if cp <= 0xFFFF: return "\\u%04X" % cp
    v = cp - 0x10000
    return "\\u%04X\\u%04X" % (0xD800 + (v >> 10), 0xDC00 + (v & 0x3FF))

rows, seen, bad = [], set(), []
section = None
out = []
for line in PROGRAMS.strip().split("\n"):
    line = line.strip()
    if line.startswith("#"):
        out.append("  // " + line.lstrip("# ").strip())
        continue
    lhs, _, glyph = line.partition(" = ")
    g = names.get(glyph.strip())
    if not g: bad.append("no such glyph: " + glyph); continue
    cp = int(g["code"], 16)
    if cp not in have: bad.append("font lacks " + glyph); continue
    keys = [k.strip() for k in lhs.split("|")]
    pairs = []
    for k in keys:
        if k in seen: bad.append("duplicate key " + k); continue
        seen.add(k); pairs.append('"%s": "%s"' % (k, esc(cp)))
    # three to a line, the way FILES and EXTS are laid out
    for i in range(0, len(pairs), 3):
        out.append("  " + ", ".join(pairs[i:i+3]) + ",")
if bad:
    print("\n".join(bad), file=sys.stderr); sys.exit(1)
if out[-1].endswith(","): out[-1] = out[-1][:-1]
print("\n".join(out))
print("// %d names" % len(seen), file=sys.stderr)
