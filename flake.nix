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

      # nixpkgsConfig = with inputs; {
      #   config = {
      #     # For NixOS - configure this at system level
      #     # .. then set useGlobalPkgs = true
      #     allowUnfree = true;
      #   };
      # };
    in {
      # ... packages bit adapted from here: https://github.com/Misterio77/nix-starter-configs/blob/main/standard/flake.nix
      packages.${system} = import ./pkgs { inherit pkgs; };

      nixosConfigurations = {
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
        #For this, separate nixos and home-manager initially...
        #... though I may have to merge again later for opengl stuff
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
        xps15 = home-manager.lib.homeManagerConfiguration {
          inherit pkgs;
          modules = [
            ./home.nix
          ];
          extraSpecialArgs = { cfgName = "xps15"; };
        };
        p53 = home-manager.lib.homeManagerConfiguration {
          inherit pkgs;
          modules = [
            ./home.nix
          ];
          extraSpecialArgs = { cfgName = "p53"; };
        };
      };
    };

};
