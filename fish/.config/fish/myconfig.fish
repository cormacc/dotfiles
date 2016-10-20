eval (dircolors -c ~/.dircolors | sed 's/>&\/dev\/null$//')

set PATH $PATH /opt/microchip/xc16/v1.26/bin /home/cormacc/bin /home/cormacc/dev/mutebutton/cd/neuromod/tools/project_framework home/cormacc/dev/go/bin /home/cormacc/.gem/ruby/2.3.0/bin
set -x GOPATH /home/cormacc/dev/go:/home/cormacc/dev/mutebutton/configurator/src/nmd.com/vendor:/home/cormacc/dev/mutebutton/configurator
#set -x GOPATH /home/cormacc/dev/go:/home/cormacc/dev/mutebutton/configurator:/home/cormacc/dev/mutebutton/configurator/src/nmd.com/vendor
set -x EDITOR /usr/bin/vim
set -x VISUAL /usr/bin/emacs

alias ijulia="ipython notebook --profile julia"
