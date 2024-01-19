{config, pkgs, ...}:

{
  xresources.properties = {
    # This is good for a 15" 4k laptop screen
    # "Xft.dpi" = 240;
    # But this is better when docked with multiple 4k 27" screens
    "Xft.dpi" = 192;
  };

  home.file.".local/bin/dock".source=./bin/dock;
}
