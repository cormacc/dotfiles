(($VERBOSE)) && echo Adding user gem directory to the path

  # On osx, prefer homebrew to system ruby...
if [ -f /usr/local/bin/ruby ]; then
  export GEM_HOME=$(/usr/local/bin/ruby -e 'print Gem.user_dir')
else
  export GEM_HOME=$(ruby -e 'print Gem.user_dir')
fi
export PATH="$GEM_HOME/bin:$PATH"
