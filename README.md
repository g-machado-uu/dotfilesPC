# dotfilesPC

My desktop's Hyprland rice, as GNU Stow packages. Like
[dotfilesLaptop](https://github.com/g-machado-uu/dotfilesLaptop), it no
longer needs ML4W installed.

It started as [ML4W OS](https://github.com/mylinuxforwork/dotfiles) 2.14.1 by
Stephan Raabe, and a lot of it is still his work. Since ML4W is licensed under
the GNU General Public License v3.0, so is this repo (see `LICENSE`). The
changes made to ML4W's files are listed under "Changes from ML4W" below.

This repo was built from the laptop repo, then this PC's own files were put
back on top (see "How this PC differs from the laptop").

## Packages

Each folder is a stow package that mirrors `~`, so `hypr/.config/hypr` becomes
`~/.config/hypr`.

| Package | Becomes | What it is |
| --- | --- | --- |
| `hypr` | `~/.config/hypr` | Hyprland config (Lua), keybindings in `conf/keybindings/gabriel.lua`, hyprlock, hypridle, HyprMod profile |
| `quickshell` | `~/.config/quickshell` | the bar and its panels, including Settings |
| `ml4w` | `~/.config/ml4w` | ML4W's scripts the rice still uses (wallpaper, cliphist, updates, toggles), settings files |
| `matugen` | `~/.config/matugen` | colours generated from the wallpaper |
| `rofi`, `swaync`, `kitty`, `fastfetch`, `btop`, `qt6ct` | `~/.config/…` | app configs |
| `gtk-2.0`, `gtk-3.0`, `gtk-4.0`, `xsettingsd`, `xresources` | `~/.gtkrc-2.0`, `~/.config/…`, `~/.Xresources` | GTK theme, ArcStarry cursor, kora icons, file-manager bookmarks |
| `fonts` | `~/.local/share/fonts/Fira_Sans` | Fira Sans, which the bar, rofi and hyprlock use |
| `cursors` | `~/.local/share/icons/ArcStarry-cursors` | the cursor theme |
| `wallpapers` | `~/Pictures/Wallpapers` | ML4W's wallpapers, including `default.jpg` (the scripts' fallback); my own are linked in from Dropbox |
| `zsh` | `~/.zshrc` | shell config |
| `ohmyposh` | `~/Documents/mytheme_v2.toml` | prompt theme `.zshrc` loads |
| `nvim`, `vim` | `~/.config/nvim`, `~/.config/vim` | LazyVim config, vimrc |
| `tmux` | `~/.config/tmux/tmux.conf` | tmux config (plugins come from TPM) |
| `voxtype` | `~/.config/voxtype/config.toml` | dictation: push-to-talk, whisper large-v3-turbo |
| `browserflags` | `~/.config/chromium-flags.conf`, `edge-flags.conf` | Wayland flags for Chromium browsers |
| `git` | `~/.gitconfig` | name, email, default branch |
| `mimeapps` | `~/.config/mimeapps.list` | default applications |
| `systemd` | `~/.config/systemd/user/hyprland-session.target` | started by `autostart.lua` |
| `xdg-desktop-portal` | `~/.config/xdg-desktop-portal/portals.conf` | Hyprland portal first |

Stow `systemd`, `xdg-desktop-portal`, `ohmyposh`, `tmux`, `voxtype` and
`wallpapers` with `--no-folding`. Otherwise stow turns the whole folder into a
link to the repo, and whatever else goes there (TPM plugins, voxtype backups,
other systemd units, my own wallpapers) ends up in the repo.

## Installing on a new machine

1. **Arch and an AUR helper.** Install Arch with a user, `git` and
   `base-devel`, clone this repo to `~/.dotfilesPC`, then bootstrap paru:

   ```bash
   git clone https://aur.archlinux.org/paru.git /tmp/paru
   (cd /tmp/paru && makepkg -si)
   ```

2. **Packages.** First the rice, then (optionally) everything else this PC
   has. `packages-arch-apps.txt` is split into sections; drop the ones that
   don't fit the new machine (NVIDIA, Intel microcode, GNOME…).

   ```bash
   cd ~/.dotfilesPC
   paru -S --needed $(grep -v '^#' packages-arch.txt)
   paru -S --needed $(grep -v '^#' packages-arch-apps.txt)
   ```

3. **Create the parent folders first,** so stow links the files inside them
   instead of turning `~/.config` itself into a link to one package:

   ```bash
   mkdir -p ~/.config ~/.local/share/icons ~/.local/share/fonts ~/Pictures ~/Documents
   ```

4. **Stow everything:**

   ```bash
   cd ~/.dotfilesPC
   stow hypr quickshell ml4w matugen rofi swaync kitty fastfetch btop qt6ct \
        gtk-2.0 gtk-3.0 gtk-4.0 xsettingsd xresources fonts cursors \
        zsh nvim vim browserflags git mimeapps
   stow --no-folding systemd xdg-desktop-portal ohmyposh tmux voxtype wallpapers
   fc-cache -f
   ```

5. **Shell, tmux plugins, my wallpapers, groups.** Sign in to Dropbox and let
   it sync first; rerun the `ln` line whenever you add a wallpaper to Dropbox.

   ```bash
   chsh -s /usr/bin/zsh
   ln -s ~/Dropbox/Wallpapers/* ~/Pictures/Wallpapers/
   git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm   # then prefix+I in tmux
   sudo usermod -aG docker,nordvpn,input,uucp,dialout,plugdev "$USER"   # skip groups that don't exist
   ```

6. **Login screen and services** (what is enabled on this PC). The SDDM
   theme is copied, not stowed (see "System files"):

   ```bash
   sudo cp -r system/usr/share/sddm/themes/ml4w /usr/share/sddm/themes/
   sudo cp system/etc/sddm.conf /etc/sddm.conf
   sudo systemctl enable sddm NetworkManager bluetooth firewalld cronie \
        systemd-timesyncd grub-btrfsd docker cups.socket fstrim.timer
   sudo systemctl enable nordvpnd plexmediaserver cockpit.socket   # if you installed them
   systemctl --user enable voxtype
   ```

7. **Log in.** Pick **Hyprland** (not "Hyprland (uwsm)") at the login screen.

## Moving this PC off ML4W

Right now ML4W's links are still live here: `~/.config/hypr` and the others
point into `~/.mydotfiles/com.ml4w.dotfiles.stable/`. Stow won't write through
a link it doesn't own, so per package:

```bash
unlink ~/.config/hypr && stow hypr
```

`unlink` only removes the link, never ML4W's files.

- **ML4W links** (unlink, then stow): `~/.config/` `hypr quickshell ml4w
  matugen rofi swaync kitty fastfetch btop qt6ct gtk-3.0 gtk-4.0 xsettingsd
  vim chromium-flags.conf edge-flags.conf`, and `~/.gtkrc-2.0`,
  `~/.Xresources`.
- **Real files** (move aside, e.g. `mv ~/.zshrc ~/.zshrc.pre-stow`, then
  stow): `~/.zshrc`, `~/.gitconfig`, `~/.config/mimeapps.list`,
  `~/.config/nvim`, `~/.config/tmux/tmux.conf`, `~/.config/voxtype/config.toml`,
  `~/Documents/mytheme_v2.toml`, `~/.local/share/icons/ArcStarry-cursors`.
- **Wallpapers:** move your own into Dropbox and link them back, then add
  ML4W's with stow:

  ```bash
  mkdir -p ~/Dropbox/Wallpapers
  mv ~/Pictures/Wallpapers/* ~/Dropbox/Wallpapers/
  ln -s ~/Dropbox/Wallpapers/* ~/Pictures/Wallpapers/
  stow --no-folding wallpapers
  ```
- **`systemd`:** `~/.config/systemd` is a real folder here holding only the
  voxtype enable link, so `stow --no-folding systemd` just adds
  `hyprland-session.target` next to it.

`stow -n <package>` shows what would happen without doing it.

**What changes at the next login:**
- waybar, the dock, the Welcome app and the separate ML4W settings app no
  longer start. The Settings panel (SUPER+SHIFT+S) replaces the settings app.
- voxtype starts at login. Its unit has been enabled all along, but it is
  wanted by `graphical-session.target`, which nothing started until
  `autostart.lua` began starting `hyprland-session.target`.

**Leftovers to delete once it has run fine for a while:** the ML4W links for
apps this repo drops (`~/.bashrc`, `~/.config/` `bashrc fish ohmyposh waybar
walker waypaper wlogout nwg-dock-hyprland ml4w-dotfiles-settings sidepad`),
`~/.local/share/ml4w-dotfiles-settings`, `~/.config/ml4w-dotfiles-installer`,
`~/.mydotfiles/`, and the packages `waybar hyprpaper nwg-dock-hyprland
hyprsysteminfo`.

## Settings

The separate ML4W settings app is replaced by a panel that drops out of the
bar. Open it with SUPER+SHIFT+S, the **Settings** button in the sidebar,
`qs ipc call settings toggle` or the `settings` alias. Its tabs:
- **Appearance:** rofi border and font, wallpaper blur, and the animation,
  decoration, window, layout and workspace variants.
- **Default apps:** terminal, browser, email, file manager, network and
  Bluetooth managers, software manager, calculator, screenshot editor, system
  monitor, and the AUR helper (paru here).
- **System:** keybinding, monitor, environment and window-rule variants.

The entries come from `quickshell/.config/quickshell/SettingsApp/settings.json`.

## Power menu

Logout, reboot and power off go through `hyprshutdown`, as the
[Hyprland wiki](https://wiki.hypr.land/Hypr-Ecosystem/hyprshutdown/)
recommends. Lock goes through `loginctl lock-session`, so hypridle starts
hyprlock; with hypridle stopped (caffeine), hyprlock runs directly. SUPER+CTRL+L
does the same. This PC uses SDDM with NVIDIA: if logging out leaves a black
screen, add `--vt <n>` to the `hyprshutdown` calls in
`quickshell/.config/quickshell/PowerApp/PowerPanel.qml`.

## How this PC differs from the laptop

- **Monitor:** one DP-1 at 3440x1440@75 (`hypr/hyprland-gui.lua` and the
  HyprMod profile in `hypr/hyprmod/`).
- **Input and look:** flat mouse acceleration, gaps 4/13, Caps Lock as Escape
  (Shift+Caps for Caps Lock), gb/br layouts on Alt+Shift.
- **Environment:** the `nvidia.lua` variant.
- **Keys:** voxtype is push-to-talk (hold SUPER+CTRL+M) instead of a toggle;
  SUPER+ALT+PRINT copies an area screenshot to the clipboard.
- **Wallpapers:** everything lives in `~/Pictures/Wallpapers`. ML4W's come
  from the `wallpapers` package; mine live in `~/Dropbox/Wallpapers` and are
  linked in one by one. They stay out of the repo because the sites they come
  from (ultrawidewallpapers.net, wallhaven, Reddit) allow personal use only.
- **Other:** paru as AUR helper, the `arch-cleanup` alias
  (`ml4w-arch-cleanup`), the pywalfox template in matugen, kitty's smaller
  first window, and this PC's own `.zshrc`, nvim, fastfetch and bookmarks.
- **Only here:** `tmux`, `voxtype`, `git`, `mimeapps` and `wallpapers`, and
  `packages-arch-apps.txt`.

## Changes from ML4W

Same as the laptop repo.

**Removed:**
- waybar and its themes
- the ML4W dock (nwg-dock-hyprland)
- walker, waypaper and wlogout configs
- the welcome app and ML4W's separate settings app
- the theme switcher (`ml4w/themes`)
- ML4W's own install and update scripts
- about 20 scripts nothing calls
- matugen outputs for the removed apps

**Replaced:**
- the settings app, with the Settings panel
- `ml4w-power`, with the `hyprshutdown` calls above
- the launcher script, with rofi only
- the status bar toggle and reload scripts, with Quickshell only

**Edited:**
- window rules use regular expressions (`.*name.*`); ML4W's `*name*` globs are
  invalid and the rules were silently skipped
- the sidebar loses Welcome, the waybar engine switch and the dock switches
- SUPER+Q also closes an open Settings panel
- the wallpaper script and GTK theme listener no longer restart waybar or the
  dock
- the autostart log is written to `~/.cache/ml4w-autostart.log`
- ML4W's wallpapers moved from `~/.config/ml4w/wallpapers` to
  `~/Pictures/Wallpapers`, so the fallback `default.jpg` and the panel's
  default folder point there; the wallpaper scripts' `find` calls follow
  symlinks (`-L`), since every wallpaper there is a link

`ML4W_BASELINE` and `./upstream-diff.sh` show what ML4W changed upstream since
2.14.1, or what this repo changed (`--mine`).

## System files

`system/` is not a stow package: it mirrors `/` and gets copied into place
with `sudo` (step 6). The SDDM greeter runs as its own user and can't follow
links into `~`.

- `system/usr/share/sddm/themes/ml4w`: the login theme. It is
  [SilentSDDM](https://github.com/uiriansan/SilentSDDM) as shipped by ML4W
  ([ml4w-sddm](https://github.com/mylinuxforwork/ml4w-sddm)), with my
  background (`backgrounds/ml4w.jpg`) and a UK date on the lock screen
  (`configs/ml4w.conf`). It needs `qt6-svg`, `qt6-virtualkeyboard` and
  `qt6-multimedia-ffmpeg`, which are in `packages-arch.txt`.
- `system/etc/sddm.conf`: selects the theme and its virtual keyboard.

After changing the theme on the live system, copy it back with
`rsync -a --exclude=.git /usr/share/sddm/themes/ml4w/ system/usr/share/sddm/themes/ml4w/`.

## Not covered by this repo

Outside `~` and not in `system/`:
- **Plymouth theme `solar`, GRUB, zram, pacman.conf** (Color,
  ParallelDownloads = 10, ILoveCandy, multilib).
- **Flatpaks:** the Settings panel's calculator and emoji-picker entries call
  `org.gnome.Calculator` and `com.tomjwatson.Emote` as flatpaks, which this PC
  doesn't have (`gnome-calculator` is installed as a package). The only
  flatpak here is `com.mattjakeman.ExtensionManager`.
- **Hand-installed:** oh-my-posh sits in `~/.local/bin` and the kora icons in
  `~/.local/share/icons`; on a new machine the AUR packages in
  `packages-arch.txt` replace both.

## Licences

- **Everything derived from ML4W:** GPL-3.0 (`LICENSE`).
- **Fira Sans:** SIL Open Font License (`fonts/.local/share/fonts/Fira_Sans/OFL.txt`).
- **ArcStarry cursors:** they came with ML4W's setup files; check the cursor
  project's own licence before publishing this repo.
- **SDDM theme (`system/`):** GPL-3.0 (its own `LICENSE`).
- **`quickshell/overview`:** a separate project, with its own README.
- **Wallpapers:** only ML4W's, as published in ML4W's own repo. My own are
  licensed for personal use only and are never added here.
