{
  description = "Home Manager configuration for CormacC";
  # See https://nix-community.github.io/home-manager/index.html

  inputs = {
    # Specify the source of Home Manager and Nixpkgs.
    nixpkgs = {
      url = "github:nixos/nixpkgs/nixos-unstable";
    };
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs@{ self, nixpkgs, home-manager, ... }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      nixpkgsConfig = with inputs; {
        config = {
          # For NixOS - configure this at system level
          # .. then set useGlobalPkgs = true
          allowUnfree = true;
          allowUnfreePredicate = (_: true);
        };
      };
    in {
      homeConfigurations.cormacc = home-manager.lib.homeManagerConfiguration {
        inherit pkgs;

        # Specify your home configuration modules here, for example,
        # the path to your home.nix.
        modules = [
          ./home.nix
        ];

        # Optionally use extraSpecialArgs
        # to pass through arguments to home.nix
      };
    };
}
