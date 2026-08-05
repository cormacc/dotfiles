{
  description = "NixOS / nix-darwin configuration";
  # See here for a well commented nixos + home-manager modular config: # https://github.com/TLATER/dotfiles

  inputs = {

    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Keep Darwin on its own input so it can be pinned independently when an
    # upstream macOS regression requires it.
    nixpkgs-darwin.url = "github:nixos/nixpkgs/nixos-unstable";
    home-manager-darwin = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs-darwin";
    };
    nix-darwin = {
      url = "github:nix-darwin/nix-darwin/master";
      inputs.nixpkgs.follows = "nixpkgs-darwin";
    };
    nix-homebrew.url = "github:zhaofengli/nix-homebrew";
    # Optional: Declarative tap management
    homebrew-core = {
      url = "github:homebrew/homebrew-core";
      flake = false;
    };
    homebrew-cask = {
      url = "github:homebrew/homebrew-cask";
      flake = false;
    };


    microchip = {
      url = "github:cormacc/nix-microchip";
      # url = "/home/cormacc/dev/nix-microchip";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # IMPORTANT: do NOT add `inputs.nixpkgs.follows` for inputs with cachix caches
    # Doing so bypasses the cache, triggering full source rebuilds.

    nur.url  = "github:nix-community/NUR";
    nix-amd-ai.url = "github:noamsto/nix-amd-ai";
    pi.url = "github:lukasl-dev/pi.nix";
    claude-code.url = "github:sadjow/claude-code-nix";

    herdr = {
      url = "github:ogulcancelik/herdr";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    claude-desktop = {
      # url = "github:aaddrick/claude-desktop-debian";
      url = "github:tomsch/claude-desktop-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    hermes-agent = {
      url = "github:NousResearch/hermes-agent";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    dirge = {
      #Latest combines commits from all my open upstream PRs
      #url = "github:cormacc/dirge/latest";
      #Upstream
      url = "github:dirge-code/dirge";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  # NOTE: nixConfig must be a literal attrset of literals — nix parses it
  # before evaluating the flake, so it cannot reference `let`-bound
  # imports. Keep this list in sync with lib/nix-caches.nix, which is the
  # source of truth for the running-system equivalents in nixos-base.nix
  # and darwin-configuration.nix.
  nixConfig = {
    # NOTE: trusted-users here only applies when the flake is evaluated by an
    # already-trusted user. For a fresh NixOS install, also set trusted-users
    # in your NixOS module (e.g. nix.settings.trusted-users in nixos-base.nix).
    trusted-users = ["root" "@wheel" "cormacc"];
    extra-substituters = [
      "https://cache.nixos.org"
      "https://nix-community.cachix.org"
      "https://pi.cachix.org"
      "https://claude-code.cachix.org"
      "https://nix-amd-ai.cachix.org"
      #Not sure whether these last two are in use...
      "https://hyprland.cachix.org"
      "https://cache.numtide.com"
    ];
    extra-trusted-gpg-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="
      "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
      "pi.cachix.org-1:lGeoGJaZ5ZDabuRzkcD5EBTNnDM4HJ1vqeOxlWk1Flk="
      "claude-code.cachix.org-1:YeXf2aNu7UTX8Vwrze0za1WEDS+4DuI2kVeWEE4fsRk="
      "nix-amd-ai.cachix.org-1:F4OU4vw/lV2oiG6SBHZ+nqjl4EFJuqI4X9A7pvaBmhQ="
    ];
  };

  outputs = { self, nixpkgs, nixpkgs-darwin, home-manager, home-manager-darwin, nix-darwin, nix-homebrew, homebrew-core, homebrew-cask, microchip, claude-code, claude-desktop, hermes-agent, rust-overlay, nur, pi, dirge, herdr, nix-amd-ai, ... } @inputs:
    let
      inherit (self) outputs;
      system = "x86_64-linux";
      linuxOverlays = [
        claude-code.overlays.default
        claude-desktop.overlays.default
        dirge.overlays.default
        herdr.overlays.default
        hermes-agent.overlays.default
        microchip.overlays.default
        nur.overlays.default
        pi.overlays.default
        rust-overlay.overlays.default
        # Local packages: pkgs/<name>/default.nix -> pkgs.<name>
        (import ./pkgs/overlay.nix)
      ];
      darwinOverlays = [
        claude-code.overlays.default
        dirge.overlays.default
        herdr.overlays.default
        pi.overlays.default
      ];
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
        overlays = linuxOverlays;
      };
    in {
      # Local packages (pkgs/<name>/default.nix) exposed as flake outputs so
      # they can be built directly, e.g. `nix build .#dirge --impure`. This is
      # the exact same attrset the overlay injects into the home/nixos `pkgs`
      # set above (callPackage-wired against the fully-overlaid pkgs), so there
      # is no duplication and new pkgs/<name>/ dirs appear automatically.
      packages.${system} = (import ./pkgs/overlay.nix) pkgs pkgs;

      nixosConfigurations = {
        # Standalone home-manager pattern (os config separate from user env)
        # is the canonical approach -- os-level tweaking should happen less
        # often than local environment changes.
        xps15 = nixpkgs.lib.nixosSystem {
          system = "${system}";
          specialArgs = {
            inherit inputs;
            hostName = "xps15";
          };
          modules = [
            { nixpkgs.config.allowUnfree = true; }
            hermes-agent.nixosModules.default
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
        # Framework Desktop / AMD Ryzen AI Max+ 395 (Strix Halo) — local LLM
        # server. Mirrors xps15's standalone-Home-Manager split: NixOS is
        # built as `.#strix`, Home Manager remains `.#default`. NVIDIA is
        # dropped (iGPU + NPU only). `inputs.nix-amd-ai.nixosModules.default`
        # supplies `hardware.amd-npu` (XRT/XDNA/Lemonade/ROCm/Vulkan).
        strix = nixpkgs.lib.nixosSystem {
          system = "${system}";
          specialArgs = {
            inherit inputs;
            hostName = "strix";
          };
          modules = [
            { nixpkgs.config.allowUnfree = true; }
            inputs.nix-amd-ai.nixosModules.default
            ./hosts/strix/hardware-configuration.nix
            ./hosts/strix/nixos-configuration.nix
            ./nixos-workstation.nix
            ./nixos-gaming.nix
          ];
        };
        t580 = nixpkgs.lib.nixosSystem {
          system = "${system}";
          specialArgs = { hostName = "t580"; };
          modules = [
            { nixpkgs.config.allowUnfree = true; }
            # If re-enabling nvidia on t580, import ./nixos-nvidia.nix and
            # set `dotfiles.nvidia.legacy = true;` -- it has a pre-Turing
            # Quadro.
            ./hosts/t580/hardware-configuration.nix
            ./nixos-boot-default.nix
            ./nixos-workstation.nix
            ./nixos-gaming.nix
          ];
        };
        # Current NAS: odroid-h4.
        nas = nixpkgs.lib.nixosSystem {
          system = "${system}";
          specialArgs = { hostName = "nas"; };
          modules = [
            hermes-agent.nixosModules.default
            ./hosts/odroid-h4/hardware-configuration.nix
            ./hosts/odroid-h4/homelab-agent.nix
            ./nixos-boot-default.nix
            #... server-only
            ./nixos-server.nix
            #... or if we want best of both worlds
            # ./nixos-workstation.nix
          ];
        };
      };

      # Agent skills + pi extensions (incl. the `agent-org-memory` Nix
      # package) live in the github:cormacc/dotagents repo, registered
      # here as a git submodule under `agents/`. To build the package
      # locally:
      #     nix build ./agents#agent-org-memory
      # Or remotely:
      #     nix build github:cormacc/dotagents#agent-org-memory

      homeConfigurations = {
        default = home-manager.lib.homeManagerConfiguration {
          inherit pkgs;
          modules = [
            ./home.nix
          ];
          extraSpecialArgs = {
            cfgName = "default";
            inherit inputs system;
          };
        };
        minimal = home-manager.lib.homeManagerConfiguration {
          inherit pkgs;
          modules = [
            ./home-core-linux.nix
          ];
          extraSpecialArgs = {
            cfgName = "minimal";
            inherit inputs system; };
        };
      };

      # Build darwin config using:
      # $ darwin-rebuild switch --flake '/Users/cormacc/dotfiles#Cormacs-MacBook-Air' --impure
      #
      # Darwin has an independent nixpkgs input so a macOS-specific pin never
      # changes the package set used by Linux hosts and Home Manager profiles.
      darwinConfigurations."Cormacs-MacBook-Air" =
        let
          darwinPkgs = import nixpkgs-darwin {
            system = "aarch64-darwin";
            config.allowUnfree = true;
            overlays = darwinOverlays;
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
            nix-homebrew.darwinModules.nix-homebrew
            {
              nix-homebrew = {
                # Install Homebrew under the default prefix
                enable = true;
                autoMigrate = true;

                # Apple Silicon Only: Also install Homebrew under the default Intel prefix for Rosetta 2
                enableRosetta = true;

                # User owning the Homebrew prefix
                user = "cormacc";

                # Optional: Declarative tap management
                taps = {
                  "homebrew/homebrew-core" = homebrew-core;
                  "homebrew/homebrew-cask" = homebrew-cask;
                };

                # Optional: Enable fully-declarative tap management
                #
                # With mutableTaps disabled, taps can no longer be added imperatively with `brew tap`.
                mutableTaps = false;

                # Optional: Declarative Homebrew tap trust entries.
                #
                # Note: The trust entries are _not_ removed if you remove them from those lists!
                # Use the `brew untrust` command to remove a trust entry.
                trust = {
                  formulae = [ ];
                  casks = [ ];
                  commands = [ ];
                  taps = [ ];
                };
              };
            }
            # Optional: Align homebrew taps config with nix-homebrew
            ({config, ...}: {
              homebrew.taps = builtins.attrNames config.nix-homebrew.taps;
            })
          ];
        };
    };

}
