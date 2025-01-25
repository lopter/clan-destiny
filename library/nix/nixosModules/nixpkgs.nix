{ config, lib, ... }:
{
  options.clan-destiny.nixpkgs.unfreePredicates = lib.mkOption {
    description = ''
      The list of unfree package names that are allowed for installation.
    '';
    type = lib.types.listOf lib.types.nonEmptyStr;
    default = [ ];
  };

  config.nixpkgs.config.allowUnfreePredicate =
    let
      unfreePredicates = config.clan-destiny.nixpkgs.unfreePredicates;
    in
    pkg: builtins.elem (lib.getName pkg) unfreePredicates;
}
