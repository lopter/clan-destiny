{ lib, self, clan-core, ... }:
let
  inherit (self.inputs) nixos-hardware;
in
{
  imports = [
    clan-core.clanModules.user-password

    nixos-hardware.nixosModules.lenovo-thinkpad-t480s

    self.nixosModules.home-kal
  ];

  nixpkgs.hostPlatform = lib.mkForce "x86_64-linux";

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  clan.clan-destiny.services = {
    vault-client.enable = true;
  };
  clan.user-password.user = "kal";

  clan-destiny.usergroups.createNormalUsers = true;

  services = {
    tailscale.enable = true;
  };
}
