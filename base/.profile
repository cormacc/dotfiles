#-------------------------------
#  dotmodule framework begin
#

#This may be overridden with impunity, but base setting squashes an error
# on some platforms if not specified elsewhere.  
export TERMINAL=xterm-256color

#Local bin directory, for dotmodule additions to the path
export PATH="$PATH:$HOME/bin"

#Modules can dump environment config in a .profile.d folder
#This method doesn't give an error when directory contains no files
#N.B. the '-xtype' argument to find resolves symbolic links to their target type
if [ -d ~/.profile.d ]; then
  echo Found .profile.d 
  find ~/.profile.d/. ! -name . -prune ! -name '.*' -name '*.sh' -xtype f -print0 | while IFS= read -r -d $'\0' autoload; do
    echo Sourcing $autoload 
    source "$autoload"
  done
fi
# dotmodule framework end
#------------------------------

#... your additions below this line ...

if test -d /usr/lib/jvm/default; then
       export JAVA_HOME=/usr/lib/jvm/default
       export JDK_HOME=/usr/lib/jvm/default
fi

export EDITOR="/usr/bin/vim"
export VISUAL="/usr/bin/vim"


