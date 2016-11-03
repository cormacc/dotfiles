
# Uncomment following line if you want red dots to be displayed while waiting for completion
export COMPLETION_WAITING_DOTS="true"

# Correct spelling for commands
setopt correct

# turn off the infernal correctall for filenames
unsetopt correctall

#-- BEGIN HISTORY --
# set some history options
setopt append_history
setopt extended_history
setopt hist_expire_dups_first
setopt hist_ignore_all_dups
setopt hist_ignore_dups
setopt hist_ignore_space
setopt hist_reduce_blanks
setopt hist_save_no_dups
setopt hist_verify
# Keep a ton of history.
HISTSIZE=100000
SAVEHIST=100000
HISTFILE=~/.zsh_history
export HISTIGNORE="ls:cd:cd -:pwd:exit:date:* --help"
#-- END HISTORY --

#We want to suppress "user@host" in prompt themes when logged in to local machine
DEFAULT_USER="$USER"

#source ~/.zgen-setup
source ~/.zplug-setup

#Modules can dump zsh environment config in a .zshrc.d folder
#This method doesn't give an error when directory contains no files
#N.B. the '-xtype' argument to find resolves symbolic links to their target type
if [[ -d ~/.zshrc.d ]]; then
    (($VERBOSE)) && echo Found .zshrc.d 
    find ~/.zshrc.d/. ! -name . -prune ! -name '.*' -name '*.zsh' -xtype f -print0 | while IFS= read -r -d $'\0' autoload; do
        (($VERBOSE)) && echo Sourcing $autoload 
        source "$autoload"
    done
fi
