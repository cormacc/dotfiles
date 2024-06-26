{ config, pkgs, ... }:

let
  commonSessionVariables = {
    #Use xdg-config layout for spacemacs
    SPACEMACSDIR = "${config.xdg.configHome}/spacemacs";
    #emacs/org need to find plantuml jar rather than binary
    PLANTUML_JAR = "${pkgs.plantuml}/lib/plantuml.jar";
  };
in {
  #User environment
  home.sessionVariables = commonSessionVariables;
  #... and environment.d for gdm, kdm etc. that don't source user profile
  systemd.user.sessionVariables = commonSessionVariables;

  programs.pandoc.enable = true;
  programs.texlive.enable = true;

  home.packages = with pkgs; [
    aspell
    aspellDicts.en
    gsettings-desktop-schemas
    # Plantuml + deps
    jdk21
    graphviz
    plantuml
    ripgrep
    # Language servers...
    # TODO: install these in project flakes instead maybe?
    cmake-language-server
  ];

  home.file.".local/bin/md2org".source=./bin/md2org;
  home.file.".local/bin/org2md".source=./bin/org2md;

  # Emacs and dependencies
  programs.emacs = {
    enable = true;
    # Using pure GTK build for wayland, but not sure it's necessary...
    package = pkgs.emacs29-pgtk;
    # package = pkgs.emacs29;
  };

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
}
