#!/usr/bin/env bash
# wrapper script for waybar with args, see https://github.com/swaywm/sway/issues/5724

pkill waybar

# Style comes from the shared ~/.config/waybar/style.css default.
waybar -c ~/.config/sway/waybar-sway.jsonc > $(mktemp -t XXXX.waybar.log)
