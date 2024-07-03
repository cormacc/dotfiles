#-------------------------------
#  dotmodule framework begin
#

#This may be overridden with impunity, but base setting squashes an error
# on some platforms if not specified elsewhere.
export TERM=xterm-256color

#Set this to non-zero when debugging to list autoloads etc.
#export VERBOSE=0
export VERBOSE=1

#TODO: Move this somewhere in .profile.d (?xorg module?)
# export TERMINAL=termite

#Local bin directory, for dotmodule additions to the path
export PATH="$HOME/bin:$PATH"

export XDG_CONFIG_HOME="${HOME}/.config"
export XDG_CACHE_HOME="${HOME}/.cache"
export XDG_DATA_HOME="${HOME}/.local/share"
export XDG_STATE_HOME="${HOME}/.local/state"

#Modules can dump environment config in a .profile.d folder
#This method doesn't give an error when directory contains no files
#N.B. the '-xtype' argument to find resolves symbolic links to their target type
#N.B. removing -xtype as osx doesn't understand it...
if [ -d ~/.profile.d ]; then
  (($VERBOSE)) && echo Found .profile.d
  #find ~/.profile.d/. ! -name . -prune ! -name '.*' -name '*.sh' -type f -print0 | while IFS= read -r -d $'\0' autoload; do
  find ~/.profile.d/. ! -name . -prune ! -name '.*' -name '*.sh' -print0 | while IFS= read -r -d $'\0' autoload; do
    (($VERBOSE)) && echo Sourcing $autoload
    #source "$autoload"
    . $autoload
  done
fi
# dotmodule framework end
#------------------------------

(($VERBOSE)) && echo Path "$PATH"


#... your additions below this line ...

if test -d /usr/lib/jvm/default; then
       export JAVA_HOME=/usr/lib/jvm/default
       export JDK_HOME=/usr/lib/jvm/default
fi

export EDITOR="/usr/bin/vim"
export VISUAL="/usr/bin/vim"

# Additions from manjaro .profile
export QT_QPA_PLATFORMTHEME="qt5ct"
export GTK2_RC_FILES="$HOME/.gtkrc-2.0"
# fix "xdg-open fork-bomb" export your preferred browser from here export
#export BROWSER=/usr/bin/brave
export BROWSER=/usr/bin/chromium

#. "$HOME/.cargo/env"
swapcapsesc

# systemd and dbus don't execute .profile -- this copies environment settings across from the login session to dbus/systemd
# See https://wiki.archlinux.org/title/Systemd/User#Environment_variables 
dbus-update-activation-environment --systemd --all
