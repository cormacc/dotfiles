#-------------------------------
#  dotmodule framework begin
#

#This may be overridden with impunity, but base setting squashes an error
# on some platforms if not specified elsewhere.
export TERM=xterm-256color

#Set this to non-zero when debugging to list autoloads etc.
export VERBOSE=0
# export VERBOSE=1

#TODO: Move this somewhere in .profile.d (?xorg module?)
# export TERMINAL=termite

#Local bin directory, for dotmodule additions to the path
#export PATH="$HOME/bin:$(ruby -e 'print Gem.user_dir')/bin:$PATH"
export PATH="$HOME/bin:$PATH"

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
# fix "xdg-open fork-bomb" export your preferred browser from here export BROWSER=/usr/bin/brave
export BROWSER=/usr/bin/brave
. "$HOME/.cargo/env"
