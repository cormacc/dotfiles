{
  description = "NixOS / nix-darwin configuration";
  # See here for a well commented nixos + home-manager modular config: # https://github.com/TLATER/dotfiles

  inputs = {
    # nixpkgs.url = "github:nixos/nixpkgs/nixos-25.05";
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    # Darwin-specific nixpkgs pin.
    #
    # nixos-unstable / release-25.11 are currently broken on darwin: the
    # libarchive 3.8.4 -> 3.8.6 backport (PR #501903, merge commit
    # 32e655fe5c81a476c2c2d6fca6b41284f1d5196e) causes direnv's checkPhase
    # (test-fish) to be killed, and the same bump is downstream of many
    # darwin builds. See https://github.com/NixOS/nixpkgs/issues/507531.
    #
    # Pin to the last bisect-verified-good commit on release-25.11 (the
    # siyuan 3.6.2 backport, immediately before the libarchive merge) until
    # upstream lands a fix. Bump or remove this once the issue is closed.
    nixpkgs-darwin.url = "github:nixos/nixpkgs/e6505dfb286ba3c2fd9226397c029f589e3ea713";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # home-manager release-25.11 to match nixpkgs-darwin / nix-darwin pins.
    # Used only by darwinConfigurations. Bump together with nixpkgs-darwin
    # once https://github.com/NixOS/nixpkgs/issues/507531 is fixed.
    home-manager-darwin = {
      url = "github:nix-community/home-manager/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs-darwin";
    };
    nixgl = {
      # url = "github:nix-community/nixGL";
      # FIXME: Awaiting merge of nvidia version parsing fix to nixgl master...
      #        See https://github.com/nix-community/nixGL/pull/187
      # TODO: Switch back to github: URL once PR #187 merges (tarball URL is not
      #       content-addressed like a commit-locked github: input).
      url = "https://github.com/phirsch/nixGL/archive/fix-versionMatch.tar.gz";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    microchip = {
      url = "github:cormacc/nix-microchip";
      # url = "/home/cormacc/dev/nix-microchip";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-darwin = {
      # Pinned to release-25.11 to match nixpkgs-darwin (also release-25.11).
      # nix-darwin enforces matching nixpkgs/nix-darwin release branches; bump
      # this together with nixpkgs-darwin once #507531 is fixed upstream.
      url = "github:nix-darwin/nix-darwin/nix-darwin-25.11";
      inputs.nixpkgs.follows = "nixpkgs-darwin";
    };
    llm-agents = {
      url = "github:numtide/llm-agents.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    claude-desktop = {
      url = "github:aaddrick/claude-desktop-debian";
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
    # NOTE: trusted-users here only applies when the flake is evaluated by an
    # already-trusted user. For a fresh NixOS install, also set trusted-users
    # in your NixOS module (e.g. nix.settings.trusted-users in nixos-base.nix).
    trusted-users = ["root" "@wheel" "cormacc"];
    extra-substituters = [
      "https://cache.nixos.org"
      "https://nix-community.cachix.org"
      "https://hyprland.cachix.org"
      "https://cache.numtide.com"
    ];
    extra-trusted-gpg-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="
      "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
    ];
  };

  outputs = { self, nixpkgs, nixpkgs-darwin, home-manager, home-manager-darwin, nix-darwin, nixgl, microchip, claude-desktop, rust-overlay, nur, llm-agents, ... } @inputs:
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
          llm-agents.overlays.default
          claude-desktop.overlays.default
        ];
      };
    in {
      nixosConfigurations = {
        # This configuration consolidates system and home directory setup...
        # TODO: Migrate to standalone home-manager (see xps15 for the preferred pattern).
        t470p = nixpkgs.lib.nixosSystem {
          system = "${system}";
          specialArgs = { hostName = "t470p"; };
          modules = [
            { nixpkgs.config.allowUnfree = true; }
            nur.modules.nixos.default
            ./nixos-nvidia.nix
            ./hosts/t470p/hardware-configuration.nix
            ./nixos-boot-default.nix
            ./nixos-workstation.nix
            ./nixos-gaming.nix
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
            ./nixos-workstation.nix
            ./nixos-gaming.nix
            #Not currently doing anything with ollama, and it takes ages to build...
            #./nixos-llm.nix
          ];
        };
        t580 = nixpkgs.lib.nixosSystem {
          system = "${system}";
          specialArgs = { hostName = "t580"; };
          modules = [
            { nixpkgs.config.allowUnfree = true; }
            # ./nixos-nvidia-legacy.nix
            ./hosts/t580/hardware-configuration.nix
            ./nixos-boot-default.nix
            ./nixos-workstation.nix
            ./nixos-gaming.nix
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
            # ./nixos-workstation.nix
          ];
        };
        #... or odroid h4
        nas = nixpkgs.lib.nixosSystem {
          system = "${system}";
          specialArgs = { hostName = "nas"; };
          modules = [
            ./hosts/odroid-h4/hardware-configuration.nix
            ./nixos-boot-default.nix
            #... server-only
            ./nixos-server.nix
            #... or if we want best of both worlds
            # ./nixos-workstation.nix
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
          extraSpecialArgs = { cfgName = "minimal"; inherit inputs system nixgl; };
        };
      };

      # Build darwin config using:
      # $ darwin-rebuild switch --flake '/Users/cormacc/dotfiles#Cormacs-MacBook-Air' --impure
      #
      # Uses nixpkgs-darwin / home-manager-darwin (pinned to release-25.11
      # last-known-good) instead of nixos-unstable. See input comment above
      # and https://github.com/NixOS/nixpkgs/issues/507531.
      darwinConfigurations."Cormacs-MacBook-Air" =
        let
          darwinPkgs = import nixpkgs-darwin {
            system = "aarch64-darwin";
            config.allowUnfree = true;
            overlays = [
              llm-agents.overlays.default
              claude-desktop.overlays.default
            ];
          };
        in
        nix-darwin.lib.darwinSystem {
          specialArgs = { inherit self inputs; };
          modules = [
            { nixpkgs.pkgs = darwinPkgs; }
            ./darwin-configuration.nix
            home-manager-darwin.darwinModules.home-manager
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.users.cormacc = import ./home-darwin.nix;
              home-manager.extraSpecialArgs = {
                cfgName = "minimal";
                inherit inputs;
              };
            }
          ];
        };
    };

}
