{ config, pkgs, ... }:

{
  home.packages = with pkgs; [
    # Compilers etc. for evaluating 3rd party repos without a flake...
    # ... clojure
    clojure
    neil
    bbin
  ];

  home.file."${config.xdg.configHome}/clojure".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/dotfiles/dev/clojure/config";
}
