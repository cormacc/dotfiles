# cormacc's dotfiles

My dotfiles in modular format.
Uses gnu stow wrapped in a ruby CLI (using thor) and some simple conventions.

## Overview

### dotmodule (Ruby CLI)

Does the following:

* Creates top level directories (`~/.profile.d`, `~/bin`, etc. )
* Invokes [GNU stow](https://www.gnu.org/software/stow/) to set up links for each module passed as a command line argument  


### Module structure

Each subdirectory is a module.

| Folder | Purpose |
|--|--|
| `.profile.d` | Shell autoloads (e.g. environment modifications etc.) |
| `bin` | Added to the path |
| | |

## Included modules

* base
* emacs
* fish
* i3
* macbook
* ruby
* ssh
* vscode
* xorg
* zsh
