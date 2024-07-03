{config, pkgs, ... }:

{
  programs.chromium.enable = true;
  programs.chromium.extensions = [
    # Bitwarden
    { id = "nngceckbapebfimnlniiiahkandclblb"; }
    # xBrowserSync
    { id = "lcbjdhceifofjlpecfpeimnnphbcjgnc"; }
  ];
}
