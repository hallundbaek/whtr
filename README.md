# whtr

A terminal weather radar and forecast viewer for Denmark. It shows an animated
DMI radar plus the local forecast in a kitty terminal.

## Requirements

- A terminal that supports the kitty graphics protocol (the script uses
  `kitten icat`), such as [kitty](https://sw.kovidgoyal.net/kitty/).
- Network access to `dmi.dk`.

The Nix package wraps the script with all runtime dependencies, including kitty.

## Usage with Nix

Run it directly without installing:

```sh
nix run github:hallundbaek/whtr
```

Install it into your profile:

```sh
nix profile install github:hallundbaek/whtr
```

## NixOS

Add the flake as an input to your system flake:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    whtr = {
      url = "github:hallundbaek/whtr";
      # Reuse your own nixpkgs rather than the flake's pinned one.
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, whtr, ... }: {
    nixosConfigurations.my-host = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        whtr.nixosModules.default
        {
          programs.whtr.enable = true;
        }
      ];
    };
  };
}
```

`programs.whtr.package` can be overridden if you want to use a different build.

## Home Manager

The same module is available for Home Manager:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    whtr = {
      url = "github:hallundbaek/whtr";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, home-manager, whtr, ... }: {
    homeConfigurations.me = home-manager.lib.homeManagerConfiguration {
      pkgs = nixpkgs.legacyPackages.x86_64-linux;
      modules = [
        whtr.homeManagerModules.default
        {
          programs.whtr.enable = true;
        }
      ];
    };
  };
}
```

## Controls

- `j` / `k`: scrub through radar frames
- `w`: refresh the forecast
- `q`: quit
