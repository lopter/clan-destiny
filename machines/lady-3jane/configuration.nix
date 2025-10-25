{
  lib,
  self,
  pkgs,
  ...
}:
let
  inherit (self.inputs) destiny-config nixos-hardware;

  enableSecureBoot = true;

  familyUserNames = builtins.attrNames destiny-config.lib.usergroups.familyUsers;
in
{
  imports = [
    nixos-hardware.nixosModules.lenovo-thinkpad-t480s

    self.nixosModules.home-kal
  ];

  nixpkgs.hostPlatform = lib.mkForce "x86_64-linux";

  boot.kernelPackages = pkgs.linuxPackages_zen;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.systemd-boot.enable = !enableSecureBoot;
  boot.lanzaboote.enable = enableSecureBoot;
  # TODO: move to new location see: https://github.com/nix-community/lanzaboote/issues/413#issuecomment-2618089667
  boot.lanzaboote.pkiBundle = lib.mkForce "/etc/secureboot";

  clan-destiny = {
    usergroups.createNormalUsers = familyUserNames;
    vault-client.enable = true;
  };

  services = {
    tailscale.enable = true;
    fwupd.enable = true;
  };
}
