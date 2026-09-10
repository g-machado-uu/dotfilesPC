#!/usr/bin/env bash
# Compare this repo with ML4W upstream.
#
#   ./upstream-diff.sh          what ML4W changed since my baseline in the
#                               folders this repo takes over (a stowed package
#                               no longer receives those changes)
#   ./upstream-diff.sh 2.15.1   the same, up to a given tag
#   ./upstream-diff.sh --mine   what I changed compared with the baseline
#   add -p to see full diffs instead of a summary
#
# The baseline is the ML4W tag in ML4W_BASELINE. Don't go by
# ~/.config/ml4w/version.json: upstream stopped bumping it.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE="$(<"$REPO/ML4W_BASELINE")"
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/dotfilesPC/ml4w-upstream"

new=""
mine=""
patch=""
for arg in "$@"; do
    case $arg in
        -p)     patch=1 ;;
        --mine) mine=1 ;;
        *)      new=$arg ;;
    esac
done

if [[ -d $CACHE/.git ]]; then
    git -C "$CACHE" fetch -q --tags origin
else
    git clone -q --filter=blob:none https://github.com/mylinuxforwork/dotfiles.git "$CACHE"
fi

# What a package takes over in ~: each ~/.config/<app> folder, or a top-level entry.
covered() { # <package dir>
    (cd "$1" && find . -mindepth 1 -maxdepth 2 -printf '%P\n') | while IFS= read -r rel; do
        case $rel in
            .config)   ;;
            .config/*) echo "$rel" ;;
            */*)       ;;
            *)         echo "$rel" ;;
        esac
    done
}

if [[ -n $mine ]]; then
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT
    git -C "$CACHE" archive "$BASE" dotfiles | tar -x -C "$tmp"
    echo "My changes compared with ML4W $BASE (matugen colour files skipped)"
    for pkg in "$REPO"/*/; do
        pkg=${pkg%/}
        while IFS= read -r rel; do
            if [[ ! -e $tmp/dotfiles/$rel ]]; then
                echo "Only in repo: ${pkg##*/}/$rel"
                continue
            fi
            diff -r ${patch:+-u} ${patch:--q} -x 'colors*' -x matugen.theme -x Appearance.colors.qml \
                "$tmp/dotfiles/$rel" "$pkg/$rel" \
                | sed "s|$tmp/dotfiles/|ML4W:|g; s|$REPO/|repo:|g" || true
        done < <(covered "$pkg")
    done
    exit 0
fi

if [[ -z $new ]]; then
    new="$(git -C "$CACHE" show origin/HEAD:hyprland-dotfiles-stable.dotinst \
        | sed -n 's/.*"tag"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
fi
paths=()
for pkg in "$REPO"/*/; do
    while IFS= read -r rel; do paths+=("dotfiles/$rel"); done < <(covered "$pkg")
done
echo "ML4W $BASE (baseline) -> $new"
if [[ -n $patch ]]; then
    git -C "$CACHE" --no-pager diff "$BASE" "$new" -- "${paths[@]}"
else
    git -C "$CACHE" --no-pager diff --stat=120 "$BASE" "$new" -- "${paths[@]}"
fi
