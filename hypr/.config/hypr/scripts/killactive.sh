#!/bin/bash

# If a Quickshell panel is open, close it instead of killing the window behind
# it (SUPER+Q should not reach the background window).
for panel in controlcentre media clipboard power wallpaper calendar settings; do
    if [ "$(qs ipc call "$panel" isOpen 2>/dev/null)" = "true" ]; then
        qs ipc call "$panel" close
        exit 0
    fi
done

hyprctl dispatch 'hl.dsp.window.close()'
