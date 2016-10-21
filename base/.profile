export TERMINAL=termite

if test -d /usr/lib/jvm/default; then
       export JAVA_HOME=/usr/lib/jvm/default
       export JDK_HOME=/usr/lib/jvm/default
fi

export PATH="$PATH:~/bin"
export EDITOR="/usr/bin/vim"
export VISUAL="/usr/bin/emacs"

#Modules can dump environment config in a .profile.d folder
#This method doesn't give an error when directory contains no files
if [ -d ~/.profile.d ]; then
  find ~/.profile.d/. ! -name . -prune ! -name '.*' -name '*.sh' -type f -print0 | while IFS= read -r -d $'\0' autoload; do
    source "$autoload"
  done
fi

