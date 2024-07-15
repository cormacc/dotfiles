{
  description = "NixOS configuration";
  # See here for a well commented nixos + home-manager modular config: # https://github.com/TLATER/dotfiles

  inputs = {
    # nixpkgs.url = "github:nixos/nixpkgs/nixos-24.05";
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, home-manager, ... } @inputs:
    let
      inherit (self) outputs;
      system = "x86_64-linux";
      # pkgs = nixpkgs.legacyPackages.${system};
      pkgs = import nixpkgs {
        system = "${system}";
        config = {
          allowUnfree = true;
          allowUnfreePredicate = _: true;
        };
      };
    in {
      nixosConfigurations = {
        # This configuration consolidates system and home directory setup...
        t470p = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = { hostName = "cc-t470p"; };
          modules = [
            ./nixos-nvidia.nix
            ./hosts/t470p/hardware-configuration.nix
            ./nixos.nix
            ./nixos-extra.nix
            home-manager.nixosModules.home-manager
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.users.cormacc = import ./home.nix;
              home-manager.extraSpecialArgs = { cfgName = "t470p"; };

              # Optionally, use home-manager.extraSpecialArgs to pass
              # arguments to home.nix
            }
          ];
        };
        #... this separate nixos and home-manager, arguably a better approach
        #    as os-level tweaking should happen less often than local environment
        xps15 = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = { hostName = "cc-xps15"; };
          modules = [
            # Nvidia packages not building as of 22/06/2024
            # ./nixos-nvidia.nix
            ./hosts/xps15/hardware-configuration.nix
            ./nixos.nix
            ./nixos-extra.nix
          ];
        };
      };

      homeConfigurations = {
        default = home-manager.lib.homeManagerConfiguration {
          inherit pkgs;
          modules = [
            ./home.nix
          ];
          extraSpecialArgs = { cfgName = "default"; };
        };
        minimal = home-manager.lib.homeManagerConfiguration {
          inherit pkgs;
          #TODO: Generate a minimal config?
          modules = [
            ./home.nix
          ];
          extraSpecialArgs = { cfgName = "minimal"; };
        };
      };
    };

}
