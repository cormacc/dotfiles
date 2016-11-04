# cormacc's dotfiles

My dotfiles in modular format.

Managed using the [dotmodule](https://github.com/cormacc/dotmodule) gem.

## Overview

See the [dotmodule](https://github.com/cormacc/dotmodule) repo for a general overview of the tool.


## dotmodule conventions

This dotmodule collection employs the following conventions:

### Binaries

The folder `~/bin` is added to the path by `.profile`. Any module additions are then placed in `<module_name>/bin/` 
and symlinked to `~/bin/` during installation

### Environment autoloads

Many of the modules include environment settings. These are placed in one or more files located at: 

    <module_name>/.profile.d/<something_descriptive>.sh

Module installation creates symlinks to these in `~/.profile.d` during module installation, they're sourced by `.profile` during shell initialisation.


## Module notes

This dotmodule collection is a pretty recent reverse engineering effort from a previously unmanaged setup on my primary work machine.

### `$ dotmodule info`

```
 Collection root:    /home/cormacc/dotfiles
 Default target:     /home/cormacc

 Shared target subdirectories:
   bin, .config, .profile.d

 Modules:
   i3, vscode, fish, ruby, zsh, emacs, xorg, base, ssh, macbook

 Core modules:
   base, zsh, emacs, ssh, ruby

```


### zsh

#### Environment autoloads

Similarly to bash, located in `<module_name>/.zshrc.d/*.zsh`, symlinked to `~/.zshrc.d` and sourced from `.zshrc`

I am aware that zshrc is only sourced for interactive shells -- anything required for non-interactive shells can be expressed in bash
and dumped in `.profile.d` instead (`.zshenv` sources `.profile`, so inherits those autoloads).

#### Plugin management frameworks

Being a bit of a shell dilettante, I've put setup in place to use the following plugin management systems:

- [zim](https://github.com/Eriner/zim)
- [zplug](https://github.com/zplug/zplug)
- [zgen](https://github.com/tarjoilija/zgen)

Can switch between them by setting a $ZSH_FRAMEWORK variable in `.zshrc`. Currently using zim as it seems by far the fastest to startup (though more restricted than than the other two).

`.zshrc` then invokes a script `~/.<framework>-setup` -- i.e. `.zim-setup`, `.zplug-setup`  etc. -- during startup.

For login shells `.zlogin` also sources `~/.<framwork>-login` if present

Plugin autoloads for zplug and zgen go in... 

- `<module_name>/.zplugrc.d/<something>.zsh`
- `<module_name>/.zgenrc.d/<something>.zsh`

Haven't had need of this yet in my short time with zim. Probably not relevant, due to more restricted scope of the framework.
