# Custom packages, that can be defined similarly to ones from nixpkgs
# You can build them using 'nix build .#example' or (legacy) 'nix-build -A example'

{ pkgs }: {
  # terraform-graph-beautifier = pkgs.callPackage ./terraform-graph-beautifier { };
  microchip-xc16 = pkgs.callPackage ./microchip-xc16 { };
  mplab-x-unwrapped = pkgs.callPackage ./mplab-x-unwrapped { };
  mplab-x = pkgs.callPackage ./mplab-x { };
}
