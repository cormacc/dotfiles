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
    # pi coding agent
    pi = {
      url = "github:lukasl-dev/pi.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    herdr = {
      url = "github:ogulcancelik/herdr";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    claude-desktop = {
      url = "github:aaddrick/claude-desktop-debian";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    hermes-agent = {
      url = "github:NousResearch/hermes-agent";
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
    # AMD AI inference stack (XRT + XDNA + FastFlowLM + Lemonade + ROCm/Vulkan
    # llama.cpp / whisper.cpp / stable-diffusion.cpp). Used by the strix host
    # (Framework Desktop / AMD Ryzen AI Max+ 395, Strix Halo).
    #
    # IMPORTANT: do NOT add `inputs.nix-amd-ai.inputs.nixpkgs.follows`. The
    # overlay is intentionally built against its own pinned nixpkgs so the
    # closure hashes match nix-amd-ai's Cachix; overriding nixpkgs forces a
    # full source rebuild of llama.cpp / whisper.cpp / sd-cpp.
    nix-amd-ai.url = "github:noamsto/nix-amd-ai";
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
      "https://hyprland.cachix.org"
      "https://cache.numtide.com"
      "https://pi.cachix.org"
      # Pre-built AMD AI packages (llama-cpp-rocm/vulkan, sd-cpp-rocm,
      # whisper-cpp-vulkan, lemonade, fastflowlm, XRT). Used by the strix
      # host; harmless on other hosts as the closure hashes won't match.
      "https://nix-amd-ai.cachix.org"
    ];
    extra-trusted-gpg-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="
      "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
      "pi.cachix.org-1:lGeoGJaZ5ZDabuRzkcD5EBTNnDM4HJ1vqeOxlWk1Flk="
      "nix-amd-ai.cachix.org-1:F4OU4vw/lV2oiG6SBHZ+nqjl4EFJuqI4X9A7pvaBmhQ="
    ];
  };

  outputs = { self, nixpkgs, nixpkgs-darwin, home-manager, home-manager-darwin, nix-darwin, microchip, claude-desktop, hermes-agent, rust-overlay, nur, pi, herdr, nix-amd-ai, ... } @inputs:
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
          microchip.overlays.default
          rust-overlay.overlays.default
          nur.overlays.default
          pi.overlays.default
          herdr.overlays.default
          claude-desktop.overlays.default
          # Local packages: pkgs/<name>/default.nix -> pkgs.<name>
          (import ./pkgs/overlay.nix)
        ];
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
            ./hosts/odroid-h4/hardware-configuration.nix
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
      # Uses nixpkgs-darwin / home-manager-darwin (pinned to release-25.11
      # last-known-good) instead of nixos-unstable. See input comment above
      # and https://github.com/NixOS/nixpkgs/issues/507531.
      darwinConfigurations."Cormacs-MacBook-Air" =
        let
          # Unstable nixpkgs side-channel for packages that need to
          # outrun the release-25.11 pin. Currently used to source
          # `babashka`: release-25.11 ships 1.12.209, but the `ot` CLI's
          # transitive `bling` -> `fireworks` -> `lasertag 0.12.0` chain
          # needs the `clojure.lang.IType` SCI binding added in bb
          # 1.12.211 (unstable currently ships 1.12.218). Drop this
          # overlay once `nixpkgs-darwin` advances past 1.12.211.
          unstablePkgs = import nixpkgs {
            system = "aarch64-darwin";
            config.allowUnfree = true;
          };
          darwinPkgs = import nixpkgs-darwin {
            system = "aarch64-darwin";
            config.allowUnfree = true;
            overlays = [
              pi.overlays.default
              claude-desktop.overlays.default
              herdr.overlays.default
              (_final: _prev: {
                inherit (unstablePkgs) babashka;
              })
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
