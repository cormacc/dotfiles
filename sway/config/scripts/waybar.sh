#!/usr/bin/env bash
# wrapper script for waybar with args, see https://github.com/swaywm/sway/issues/5724

pkill waybar

waybar > $(mktemp -t XXXX.waybar.log)
