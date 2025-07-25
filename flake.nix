{
  description = "NixOS configuration";
  # See here for a well commented nixos + home-manager modular config: # https://github.com/TLATER/dotfiles

  inputs = {
    # nixpkgs.url = "github:nixos/nixpkgs/nixos-25.05";
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixgl = {
      url = "github:nix-community/nixGL";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    microchip = {
      url = "github:cormacc/nix-microchip";
      # url = "/home/cormacc/dev/nix-microchip";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    claude = {
      url = "github:k3d3/claude-desktop-linux-flake";
      inputs.nixpkgs.follows = "nixpkgs";
      # inputs.flake-utils.follows = "flake-utils";
    };
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  nixConfig = {
    trusted-users = ["root" "@wheel" "cormacc"];
    extra-substituters = [
      "https://nix-community.cachix.org"
    ];
    extra-trusted-gpg-public-keys = [
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    ];
  };

  outputs = { self, nixpkgs, home-manager, nixgl, microchip, claude, rust-overlay, ... } @inputs:
    let
      inherit (self) outputs;
      system = "x86_64-linux";
      # pkgs = nixpkgs.legacyPackages.${system};
      pkgs = import nixpkgs {
        system = "${system}";
        config = {
          allowUnfree = true;
          allowUnfreePredicate = _: true;
          permittedInsecurePackages = [
            #This is ignored...
            "segger-jlink-qt4-810"
          ];
          segger-jlink.acceptLicense = true;
        };
        overlays = [
          nixgl.overlay
          microchip.overlays.default
          rust-overlay.overlays.default
        ];
      };
    in {
      nixosConfigurations = {
        # This configuration consolidates system and home directory setup...
        t470p = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = { hostName = "t470p"; };
          modules = [
            ./nixos-nvidia.nix
            ./hosts/t470p/hardware-configuration.nix
            ./hosts/nixos-configuration-default.nix
            ./nixos.nix
            ./nixos-extra.nix
            home-manager.nixosModules.home-manager
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.users.cormacc = import ./home.nix;
              home-manager.extraSpecialArgs = { cfgName = "default"; };

              # Optionally, use home-manager.extraSpecialArgs to pass
              # arguments to home.nix
            }
          ];
        };
        #... this separate nixos and home-manager, arguably a better approach
        #    as os-level tweaking should happen less often than local environment
        xps15 = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = {
            inherit inputs;
            hostName = "xps15";
          };
          modules = [
            ./nixos-nvidia.nix
            ./hosts/xps15/hardware-configuration.nix
            ./hosts/xps15/nixos-configuration.nix
            ./nixos.nix
            ./nixos-extra.nix
            ./nixos-llm.nix
          ];
        };
        t580 = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = { hostName = "t580"; };
          modules = [
            # ./nixos-nvidia-legacy.nix
            ./hosts/t580/hardware-configuration.nix
            ./hosts/nixos-configuration-default.nix
            ./nixos.nix
            ./nixos-extra.nix
          ];
        };
        # Retiring C2750D box as nas...
        # nas = nixpkgs.lib.nixosSystem {
        #   system = "x86_64-linux";
        #   specialArgs = { hostName = "nas"; };
        #   modules = [
        #     ./hosts/c2750d4i/hardware-configuration.nix
        #     ./hosts/c2750d4i/nixos-configuration.nix
        #     ./nixos-server.nix
        #   ];
        # };
        #... in favour of t470p
        t470-nas = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = { hostName = "t470-nas"; };
          modules = [
            ./hosts/t470p/hardware-configuration.nix
            ./hosts/t470p/nixos-configuration.nix
            #... server-only
            ./nixos-server.nix
            #... or if we want best of both worlds
            # ./nixos.nix
          ];
        };
        #... or odroid h4
        nas = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = { hostName = "nas"; };
          modules = [
            ./hosts/odroid-h4/hardware-configuration.nix
            ./hosts/nixos-configuration-default.nix
            #... server-only
            ./nixos-server.nix
            #... or if we want best of both worlds
            # ./nixos.nix
          ];
        };
      };

      homeConfigurations = {
        default = home-manager.lib.homeManagerConfiguration {
          inherit pkgs;
          modules = [
            ./home.nix
          ];
          extraSpecialArgs = {
            cfgName = "default";
            inherit inputs system nixgl;
          };
        };
        minimal = home-manager.lib.homeManagerConfiguration {
          inherit pkgs;
          modules = [
            ./home-core.nix
          ];
          extraSpecialArgs = { cfgName = "minimal"; };
        };
      };
    };

}
