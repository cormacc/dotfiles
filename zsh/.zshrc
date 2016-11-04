# From http://unix.stackexchange.com/questions/71253/what-should-shouldnt-go-in-zshenv-zshrc-zlogin-zprofile-zlogout
#
# - .zshenv is always sourced, it often contains exported variables that should be available to other programs. For example, $PATH, $EDITOR, and $PAGER are often set in .zshenv. Also, you can set $ZDOTDIR in .zshenv to specify an alternative location for the rest of your zsh configuration.
# - .zshrc is for interactive shell configuration. You set options for the interactive shell there with the setopt and unsetopt commands. You can also load shell modules, set your history options, change your prompt, set up zle and completion, et cetera. You also set any variables that are only used in the interactive shell (e.g. $LS_COLORS).
# - .zlogin is sourced on the start of a login shell. This file is often used to start X using startx. Some systems start X on boot, so this file is not always very useful.
# - .zprofile is basically the same as .zlogin except that it's sourced directly before .zshrc is sourced instead of directly after it. According to the zsh documentation, ".zprofile is meant as an alternative to `.zlogin' for ksh fans; the two are not intended to be used together, although this could certainly be done if desired."
# - .zlogout is sometimes used to clear and reset the terminal.


# Uncomment following line if you want red dots to be displayed while waiting for completion
export COMPLETION_WAITING_DOTS="true"

# Enable command correction prompts
# See: http://zsh.sourceforge.net/Doc/Release/Options.html#Input_002fOutput
setopt correct

# turn off the infernal correctall for filenames
unsetopt correctall


#-------------
#-- HISTORY --
# set some history options
# See http://zsh.sourceforge.net/Doc/Release/Options.html
#This allows eg. 'sudo !!' to prefix the previous command
setopt bang_hist
setopt append_history
setopt inc_append_history
setopt extended_history
setopt hist_expire_dups_first
unsetopt hist_ignore_all_dups
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
#-- HISTORY --
#-------------

#We want to suppress "user@host" in prompt themes when logged in to local machine
DEFAULT_USER="$USER"

#----------------------------
#-- PLUGIN FRAMEWORK SETUP --
#zim, zplug or zgen
export ZSH_FRAMEWORK=zim
source ~/."$ZSH_FRAMEWORK"-setup
#-- PLUGIN FRAMEWORK SETUP --
#----------------------------

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
