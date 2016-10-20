export TERMINAL=termite

if test -d /usr/lib/jvm/default; then
       export JAVA_HOME=/usr/lib/jvm/default
       export JDK_HOME=/usr/lib/jvm/default
fi

export PATH="$PATH:~/bin"
export EDITOR="/usr/bin/emacs"
export VISUAL="/usr/bin/emacs"

#Modules can dump environment config in a .profile.d folder
if test -d ~/.profile.d; then
    for autoload in ~/.profile.d/*.sh; do
        test -r "$autoload" && . "$autoload"
    done
    unset autoload
fi

