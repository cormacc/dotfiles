{ config, pkgs, ... }:

{
  home.packages = with pkgs; [
    # Compilers etc. for evaluating 3rd party repos without a flake...
    jdk24
    # ... clojure
    clojure
    polylith
    neil
    bbin
  ];

  home.file."${config.xdg.configHome}/clojure".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/dotfiles/dev/clojure/config";
}
