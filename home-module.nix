{ self }:

{ config, lib, pkgs, ... }:

let
  cfg = config.programs.whtr;
in
{
  options.programs.whtr = {
    enable = lib.mkEnableOption "the whtr terminal weather radar viewer";

    package = lib.mkOption {
      type = lib.types.package;
      default = self.packages.${pkgs.stdenv.hostPlatform.system}.default;
      defaultText = lib.literalExpression "whtr.packages.\${pkgs.stdenv.hostPlatform.system}.default";
      description = "The whtr package to install.";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ cfg.package ];
  };
}
