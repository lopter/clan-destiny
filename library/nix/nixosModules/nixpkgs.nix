{ config, lib, ... }:
{
  options.clan-destiny.nixpkgs = {
    unfreePredicates = lib.mkOption {
      description = ''
        The list of unfree package names that are allowed for installation.
      '';
      type = lib.types.listOf lib.types.nonEmptyStr;
      default = [ ];
    };
    insecurePackages = lib.mkOption {
      description = ''
        The list of insecure package names that are allowed for installation.
      '';
      type = lib.types.listOf lib.types.nonEmptyStr;
      default = [ ];
    };
  };

  config.nixpkgs.config =
  let
    allowed = allowList: pkg: builtins.elem (lib.getName pkg) allowList;
    cfg = config.clan-destiny.nixpkgs;
  in
  {
    allowUnfreePredicate = allowed cfg.unfreePredicates;
    allowInsecurePredicate = allowed cfg.insecurePackages;
  };
}
