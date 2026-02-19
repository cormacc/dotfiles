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
      # url = "github:nix-community/nixGL";
      # FIXME: Awaiting merge of nvidia version parsing fix to nixgl master...
      #        See https://github.com/nix-community/nixGL/pull/187
      url = "https://github.com/phirsch/nixGL/archive/fix-versionMatch.tar.gz";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    microchip = {
      url = "github:cormacc/nix-microchip";
      # url = "/home/cormacc/dev/nix-microchip";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    claude-code = {
      url = "github:sadjow/claude-code-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Nix User Repository
    nur = {
      url = "github:nix-community/NUR";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  nixConfig = {
    trusted-users = ["root" "@wheel" "cormacc"];
    extra-substituters = [
      "https://cache.nixos.org"
      "https://nix-community.cachix.org"
      "https://hyprland.cachix.org"
      "https://claude-code.cachix.org"
    ];
    extra-trusted-gpg-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="
      "claude-code.cachix.org-1:YeXf2aNu7UTX8Vwrze0za1WEDS+4DuI2kVeWEE4fsRk="
    ];
  };

  outputs = { self, nixpkgs, home-manager, nixgl, microchip, claude-code, rust-overlay, nur, ... } @inputs:
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
          nur.overlays.default
          claude-code.overlays.default
        ];
      };
    in {
      nixosConfigurations = {
        # This configuration consolidates system and home directory setup...
        t470p = nixpkgs.lib.nixosSystem {
          system = "${system}";
          specialArgs = { hostName = "t470p"; };
          modules = [
            nur.modules.nixos.default
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
          system = "${system}";
          specialArgs = {
            inherit inputs;
            hostName = "xps15";
          };
          modules = [
            { nixpkgs.config.allowUnfree = true; }
            # envfs.nixosModules.envfs
            ./nixos-nvidia.nix
            ./hosts/xps15/hardware-configuration.nix
            ./hosts/xps15/nixos-configuration.nix
            ./nixos.nix
            ./nixos-extra.nix
            #Not currently doing anything with ollama, and it takes ages to build...
            #./nixos-llm.nix
          ];
        };
        t580 = nixpkgs.lib.nixosSystem {
          system = "${system}";
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
        #   system = "${system}";
        #   specialArgs = { hostName = "nas"; };
        #   modules = [
        #     ./hosts/c2750d4i/hardware-configuration.nix
        #     ./hosts/c2750d4i/nixos-configuration.nix
        #     ./nixos-server.nix
        #   ];
        # };
        #... in favour of t470p
        t470-nas = nixpkgs.lib.nixosSystem {
          system = "${system}";
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
          system = "${system}";
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
            ./home-linux.nix
          ];
          extraSpecialArgs = { cfgName = "minimal"; };
        };
      };
    };

}
