{
  description = "Terminal weather radar and forecast viewer for Denmark";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

      forAllSystems = f:
        nixpkgs.lib.genAttrs systems (system: f (import nixpkgs { inherit system; }));

      nixosModule = import ./module.nix { inherit self; };
      homeManagerModule = import ./home-module.nix { inherit self; };
    in
    {
      packages = forAllSystems (pkgs: rec {
        whtr = pkgs.callPackage ./package.nix { };
        default = whtr;
      });

      apps = forAllSystems (pkgs: rec {
        whtr = {
          type = "app";
          program = nixpkgs.lib.getExe self.packages.${pkgs.stdenv.hostPlatform.system}.whtr;
          meta = {
            description = "Terminal weather radar and forecast viewer for Denmark";
          };
        };
        default = whtr;
      });

      overlays.default = final: _prev: {
        whtr = self.packages.${final.stdenv.hostPlatform.system}.default;
      };

      nixosModules = {
        default = nixosModule;
        whtr = nixosModule;
      };

      homeManagerModules = {
        default = homeManagerModule;
        whtr = homeManagerModule;
      };
    };
}
