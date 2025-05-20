{config, pkgs, nixgl, ... }:

{
  programs.chromium = {
    enable = true;
    package = config.lib.nixGL.wrap pkgs.chromium;
    extensions = [
      # Bitwarden
      { id = "nngceckbapebfimnlniiiahkandclblb"; }
      # xBrowserSync
      { id = "lcbjdhceifofjlpecfpeimnnphbcjgnc"; }
      # Shadow-cljs UI
      { id = "hpcbebiekdogcnamniekdaknicncdban"; }
      # OPFS explorer
      { id = "acndjpgkpaclldomagafnognkcgjignd"; }
    ];
  };

  # See https://github.com/kuba2k2/firefox-webserial for webserial API polyfill/extension ...
  # N.B. The provided native executable for linux is dynamically linked -- I'll need to recompile
  #      from the repo to use on nixos
  programs.firefox = {
    enable = true;
    package = config.lib.nixGL.wrap pkgs.firefox-devedition;
  };

}
