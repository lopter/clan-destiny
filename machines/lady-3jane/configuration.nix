{ lib, self, ... }:
let
  inherit (self.inputs) nixos-hardware;
in
{
  imports = [
    nixos-hardware.nixosModules.lenovo-thinkpad-t480s

    self.nixosModules.home-kal
  ];

  nixpkgs.hostPlatform = lib.mkForce "x86_64-linux";

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  clan-destiny.usergroups.createNormalUsers = true;

  services = {
    tailscale.enable = true;
  };
}
