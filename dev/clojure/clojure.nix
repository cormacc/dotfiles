{ config, pkgs, ... }:

{
  home.packages = with pkgs; [
    # Compilers etc. for evaluating 3rd party repos without a flake...
    jdk25
    clojure
    # ... editor support
    clj-kondo
    joker
    # ... CLI support
    polylith
    neil
    bbin
  ];

  home.file."${config.xdg.configHome}/clojure".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/dotfiles/dev/clojure/config";
}
