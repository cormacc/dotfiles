{ lib, config, pkgs, ... }:
with lib;
let
  dotRoot = config.my.emacs.dotRoot;
in {
  options.my.emacs = {
    dotRoot = mkOption {
      type = types.path;
      default = "";
    };
  };

  config = {

    home.packages = with pkgs; [
      #= emacs =
      aspell
      aspellDicts.en
      plantuml-c4
    ];

    home.sessionVariables = {
      #Use xdg-config layout for spacemacs
      SPACEMACSDIR = "${config.xdg.configHome}/spacemacs";
    };

    home.file.".local/bin/md2org".source="${dotRoot}/emacs/bin/md2org";
    home.file.".local/bin/org2md".source="${dotRoot}/emacs/bin/org2md";


    # Emacs and dependencies
    programs.emacs = {
      enable = true;
      package = pkgs.emacs29-gtk3;
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
    home.file."${config.xdg.configHome}/spacemacs".source = ~/dotfiles/emacs/.config/spacemacs;

    programs.pandoc.enable = true;

  };
}
