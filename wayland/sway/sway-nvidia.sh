#Run as root
# .... bypass the GDM nvidia check (prevents wayland sessions showing up)
ln -s /dev/null /etc/udev/rules.d/61-gdm.rules
# .... create a new sway session entry with the --unsupported-gpu option
cp sway-nvidia.desktop /usr/share/wayland-sessions
