(($VERBOSE)) && echo Adding user gem directory to the path
export PATH="$(ruby -e 'print Gem.user_dir')/bin:$PATH"
