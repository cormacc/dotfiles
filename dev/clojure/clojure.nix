{ config, pkgs, ... }:

let
  brepl = pkgs.callPackage (pkgs.fetchFromGitHub {
    owner = "licht1stein";
    repo = "brepl";
    rev = "v2.6.3";
    hash = "sha256-1r+7DQcfOSD9gaBE3Hu961Se5lUqxIHPzF4E2NaNl/E=";
  } + "/package.nix") {};
in
{
  home.packages = with pkgs; [
    # Compilers etc. for evaluating 3rd party repos without a flake...
    jdk25
    # ... replace jdk with these next two if we want to use GraalVM/WASM
    # binaryen
    # graalvmPackages.graalvm-oracle
    clojure
    babashka
    bbin
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
