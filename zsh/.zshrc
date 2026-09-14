# -----------------------------------------------------
# INIT
# -----------------------------------------------------
fastfetch
# -----------------------------------------------------
# Exports
# -----------------------------------------------------
export EDITOR=nvim
export ZSH="$HOME/.oh-my-zsh"
export PATH=$PATH:~/.cargo/bin/
export PATH=$PATH:~/.local/bin/
export PATH=$PATH:/home/gabriel/texlive/bin/x86_64-linux/
export INFOPATH=$INFOPATH:/home/gabriel/texlive/texmf-dist/doc/info
export MANPATH=$MANPATH:/home/gabriel/texlive/texmf-dist/doc/man


# -----------------------------------------------------
# Set-up FZF key bindings (CTRL R for fuzzy history finder)
# -----------------------------------------------------
source <(fzf --zsh)

# History
HISTSIZE=5000
HISTFILE=~/.zsh_history
SAVEHIST=$HISTSIZE
HISTDUP=erase
setopt appendhistory
setopt sharehistory
setopt hist_ignore_space
setopt hist_ignore_all_dups
setopt hist_save_no_dups
setopt hist_ignore_dups
setopt hist_find_no_dups

# Completion styling
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Za-z}'
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"
zstyle ':completion:*' menu no
zstyle ':fzf-tab:complete:cd:*' fzf-preview 'ls --color $realpath'
zstyle ':fzf-tab:complete:__zoxide_z:*' fzf-preview 'ls --color $realpath'

autoload edit-command-line; zle -N edit-command-line
bindkey '^v' edit-command-line
# -----------------------------------------------------
# Prompt
# -----------------------------------------------------
eval "$(oh-my-posh init zsh --config $HOME/Documents/mytheme_v2.toml)"

# ALIASES
# -----------------------------------------------------

# -----------------------------------------------------
# General
# -----------------------------------------------------
alias c='clear'
alias nf='fastfetch'
alias pf='fastfetch'
alias ff='fastfetch'
alias ls='eza --icons=always'
alias ll='eza -l --icons=always'
alias lt='eza --tree --level=1 --icons=always'
alias lsa='eza -a --icons=always'
alias lla='eza -al --icons=always'
alias lta='eza -a --tree --level=1 --icons=always'
alias shutdown='systemctl poweroff'
alias cd='z'
alias v='$EDITOR'
alias vim='$EDITOR'
alias wifi='nmtui'
alias arch-cleanup='~/.config/ml4w/scripts/ml4w-arch-cleanup'
alias apps='~/.config/ml4w/bin/ml4w-apps'
alias screenshot='~/.config/ml4w/bin/ml4w-screenshot'
alias updates='~/.config/ml4w/scripts/ml4w-install-system-updates'
alias filemanager='~/.config/ml4w/settings/filemanager'
alias lock='hyprlock'
alias clock='tty-clock'
alias system='~/.config/ml4w/settings/systemmonitor'
alias quick='~/.config/ml4w/bin/ml4w-quicklinks'
alias wallpaper='~/.config/ml4w/bin/ml4w-wallpaper'
alias settings='qs ipc call settings toggle'
alias venv='source ~/venv/bin/activate'
alias notes='venv && cd /mnt/Old_Arch/Ulster/Modules/2025-2026/EEE416/EEE416_Lecture_Notes/'
alias bg='kitten @ set-background-opacity'
# -----------------------------------------------------
# ML4W Apps
# -----------------------------------------------------

alias ml4w-settings='qs ipc call settings toggle'
alias ml4w-calendar='qs ipc call calendar toggle'
alias ml4w-hyprland='flatpak run com.ml4w.hyprlandsettings'
alias ml4w-sidebar='qs ipc call controlcentre toggle'

# -----------------------------------------------------
# Scripts
# -----------------------------------------------------
alias ascii='~/.config/ml4w/scripts/figlet.sh'

# -----------------------------------------------------
# System
# -----------------------------------------------------

alias update-grub='sudo grub-mkconfig -o /boot/grub/grub.cfg'

# -----------------------------------------------------
# CMAKE STM32
# -----------------------------------------------------
alias cmake_debug='cmake -B build -S . -DCMAKE_TOOLCHAIN_FILE=toolchain-arm-none-eabi.cmake -DCMAKE_BUILD_TYPE=Debug && ln -sf build/compile_commands.json compile_commands.json'
alias cmake_release='cmake -B build-release -S . -DCMAKE_TOOLCHAIN_FILE=toolchain-arm-none-eabi.cmake -DCMAKE_BUILD_TYPE=Release'
# -----------------------------------------------------
# Zinit
# -----------------------------------------------------

ZINIT_HOME="${XDG_DATA_HOME:-${HOME}/.local/share}/zinit/zinit.git"
[ ! -d $ZINIT_HOME ] && mkdir -p "$(dirname $ZINIT_HOME)"
[ ! -d $ZINIT_HOME/.git ] && git clone https://github.com/zdharma-continuum/zinit.git "$ZINIT_HOME"
source "${ZINIT_HOME}/zinit.zsh"

# Add in zsh plugins
zinit light zsh-users/zsh-syntax-highlighting
zinit light zsh-users/zsh-completions
zinit light zsh-users/zsh-autosuggestions
zinit light Aloxaf/fzf-tab

# Add in snippets
zinit snippet OMZL::git.zsh
zinit snippet OMZP::git
zinit snippet OMZP::sudo
zinit snippet OMZP::archlinux
zinit snippet OMZP::command-not-found

# Load completions
autoload -Uz compinit && compinit

zinit cdreplay -q

nvim() {
    kitty @ set-background-opacity 0.88
    command nvim "$@"
    kitty @ set-background-opacity 0.7
}
# -----------------------------------------------------
# PATH
# -----------------------------------------------------
export PATH="$HOME/.local/bin:$PATH"
export PATH="$HOME/go/bin:$PATH"
# -----------------------------------------------------
# Open the python venv automatically
# -----------------------------------------------------
# venv
# -----------------------------------------------------
# Yazi
# -----------------------------------------------------
function y() {
	local tmp="$(mktemp -t "yazi-cwd.XXXXXX")" cwd
	command yazi "$@" --cwd-file="$tmp"
	IFS= read -r -d '' cwd < "$tmp"
	[ "$cwd" != "$PWD" ] && [ -d "$cwd" ] && builtin cd -- "$cwd"
	rm -f -- "$tmp"
}
alias yc="cd /home/gabriel/.config && y"
# -----------------------------------------------------
# SSH Agent 
# -----------------------------------------------------
# eval "$(ssh-agent -s)"

# -----------------------------------------------------
# ZOXIDE
# ------------------------------------------------------

eval "$(zoxide init zsh)"
