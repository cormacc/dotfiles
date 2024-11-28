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
    ];
  };

}
