{ config, pkgs, inputs, ... }:

let
  # Emacs is held at 30.2 via the rev-pinned `nixpkgs-emacs` flake input --
  # 31.1 breaks this config, and nixpkgs no longer carries an `emacs30-*`
  # attribute. Everything else here still comes from the tracking nixpkgs.
  pkgsEmacs = import inputs.nixpkgs-emacs {
    inherit (pkgs.stdenv.hostPlatform) system;
    config.allowUnfree = true;
  };

  commonSessionVariables = {
    #Use xdg-config layout for spacemacs
    SPACEMACSDIR = "${config.xdg.configHome}/spacemacs";
    #emacs/org need to find plantuml jar rather than binary
    PLANTUML_JAR = "${pkgs.plantuml}/lib/plantuml.jar";
  };
in {
  imports = [ inputs.nix-doom-emacs-unstraightened.homeModule ];

  #User environment
  home.sessionVariables = commonSessionVariables;
  #... and environment.d for gdm, kdm etc. that don't source user profile
  systemd.user.sessionVariables = commonSessionVariables;

  programs.pandoc.enable = true;
  programs.texlive.enable = true;

  home.packages = with pkgs; [
    # aspell
    # aspellDicts.en
    # aspellDicts.ga
    (aspellWithDicts (dicts: with dicts; [en en-computers en-science ga]))
    source-code-pro
    ripgrep
    gsettings-desktop-schemas
    #vterm deps
    # .. This is old/broken -- see https://weblog.zamazal.org/sw-problem-nixos-emacs-vterm/
    # libvterm
    # ... This allegedly isn't
    libvterm-neovim
    # org export
    zip #for ODT export
    # Other...
    libtool
    cmake
    gnumake
    gcc
    # charts
    plantuml
    # plantuml-c4
    # jdk21
    graphviz
    mermaid-cli
    # Layer dependencies.
    # TODO: install these in project flakes instead maybe?
    #       ... though the layers are enabled in global config ...
    # ... bash
    bash-language-server
    # ... c/c++
    # FIXME: Causing an installation error as of 26/08/2025
    # cmake-language-server
    clang-tools
    # ... python
    pyright
    black
    # ... clojure
    clj-kondo
    joker
    clojure-lsp
    # ...
  ];

  home.file.".local/bin/md2org".source=./bin/md2org;
  home.file.".local/bin/org2md".source=./bin/org2md;

  # Emacs and dependencies
  programs.emacs = {
    enable = true;
    # Using pure GTK build for wayland, but not sure it's necessary...
    # Pinned package set -- see `pkgsEmacs` above.
    package = pkgsEmacs.emacs-pgtk;
    extraPackages = (epkgs: [ epkgs.vterm ]);
  };
  services.emacs = {
    enable = true;
    client.enable = true;
    # defaultEditor = true;
  };


  # Spacemacs

  home.file."${config.xdg.configHome}/emacs" = {
    recursive = true;
    #Use this variant to pin a specific commit
    # source = pkgs.fetchFromGitHub {
    #   owner = "syl20bnr";
    #   repo = "spacemacs";
    #   rev = "e4b20f797d9e7a03d9a5603942c4a51ea19047b2";
    #   #N.B. If updating rev above, new sha256 will be reported when trying to swap this flake in, and can be pasted here
    #   sha256 = "OdZuOmxDYvvsCnu9TcogCeB0agCq8o20/YPCmUSwYPw=";
    # };
    #... or this variant to track a branch
    source = builtins.fetchGit {
      url = "https://github.com/syl20bnr/spacemacs";
      ref = "develop";
    };
  };
  # Do this to have a symlinked read-only version
  # home.file."${config.xdg.configHome}/spacemacs".source = .config/spacemacs;
  # ... or this to keep it editable in-place, rather than have to 'home-manager switch ...' after each edit
  home.file."${config.xdg.configHome}/spacemacs".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/dotfiles/editors/emacs/spacemacs";


  # Doom emacs
  programs.doom-emacs = {
    enable = true;
    provideEmacs = false;
    doomDir = ./doom;
  };


  # Corgi emacs... a clojure-focused minimal config with spacemacs-like keybindings
  # See https://github.com/corgi-emacs/corgi

  # Keep the config files editable in place, but leave the containing directory
  # writable so Emacs runtime state does not end up in the dotfiles repository.
  xdg.configFile."emacs-corgi/bootstrap.el".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/dotfiles/editors/emacs/corgi/bootstrap.el";
  xdg.configFile."emacs-corgi/early-init.el".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/dotfiles/editors/emacs/corgi/early-init.el";
  xdg.configFile."emacs-corgi/init.el".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/dotfiles/editors/emacs/corgi/init.el";
  xdg.configFile."emacs-corgi/user-keys.el".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/dotfiles/editors/emacs/corgi/user-keys.el";
  xdg.configFile."emacs-corgi/user-signals.el".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/dotfiles/editors/emacs/corgi/user-signals.el";

  home.shellAliases = {
    demacs = "doom-emacs";
    cemacs = "emacs --init-dir ~/.config/emacs-corgi";
  };
}
