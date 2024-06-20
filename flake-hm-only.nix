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
      homeConfigurations.p53 = home-manager.lib.homeManagerConfiguration {
        inherit pkgs;

        # Specify your home configuration modules here, for example,
        # the path to your home.nix.
        modules = [
          ./home.nix
          ./desktop.nix
          ./unfree.nix
          ./emacs/emacs.nix
          ./nmd/nmd.nix
          #could either do host-specifics here, e.g.
          ./hosts/p53/home-p53.nix
          ./i3/i3.nix
        ];

        # ... or use extraSpecialArgs
        # to pass through arguments to home.nix
        extraSpecialArgs = {
          host = "p53";
          # withGUI = true;
          # isDesktop = true;
          # networkInterface = "enp5s0";
          # inherit localOverlay;
        };
      };
      homeConfigurations.xps15 = home-manager.lib.homeManagerConfiguration {
        inherit pkgs;

        # Specify your home configuration modules here, for example,
        # the path to your home.nix.
        modules = [
          ./home.nix
          ./desktop.nix
          ./unfree.nix
          ./emacs/emacs.nix
          ./nmd/nmd.nix
          #could either do host-specifics here, e.g.
          # ./hosts/xps15/home-xps15.nix
          ./sway/sway.nix
        ];

        # ... or use extraSpecialArgs
        # to pass through arguments to home.nix
        extraSpecialArgs = {
          host = "xps15";
          # withGUI = true;
          # isDesktop = true;
          # networkInterface = "enp5s0";
          # inherit localOverlay;
        };
      };
      homeConfigurations.wsl = home-manager.lib.homeManagerConfiguration {
        inherit pkgs;

        # Specify your home configuration modules here, for example,
        # the path to your home.nix.
        modules = [
          ./home.nix
          #could either do host-specifics here, e.g.
          # ./hosts/xps15/home-wsl.nix
        ];

        # ... or use extraSpecialArgs
        # to pass through arguments to home.nix
        extraSpecialArgs = {
          host = "wsl";
        };
      };

    };
}
