#!/usr/bin/env bash
# wrapper script for waybar with args, see https://github.com/swaywm/sway/issues/5724

pkill waybar

waybar -c ~/.config/sway/waybar-sway.jsonc -s ~/.config/sway/waybar-sway.css > $(mktemp -t XXXX.waybar.log)
