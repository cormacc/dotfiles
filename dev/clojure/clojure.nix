{ config, pkgs, ... }:

{
  home.packages = with pkgs; [
    # Compilers etc. for evaluating 3rd party repos without a flake...
    jdk25
    # ... replace jdk with these next two if we want to use GraalVM/WASM
    # binaryen
    # graalvmPackages.graalvm-oracle
    clojure
    # Installed via shell.nix
    # babashka
    # bbin
    # ... editor support
    clojure-lsp
    clj-kondo
    joker
    parinfer-rust-emacs
    # ... CLI support
    polylith
    leiningen
    neil
    # ... nrepl connections for claude etc. -- see https://github.com/licht1stein/brepl
    # brepl
  ];

  home.file."${config.xdg.configHome}/clojure".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/dotfiles/dev/clojure/config";
}
