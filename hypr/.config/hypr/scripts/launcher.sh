#!/usr/bin/env bash
# Toggle the rofi application launcher.
pkill rofi || rofi -show drun -replace -i
