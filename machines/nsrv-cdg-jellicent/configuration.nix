{ lib, self, ... }:
let
  inherit (self.inputs) nixos-hardware;
in
{
  imports = [
    nixos-hardware.nixosModules.aoostar-r1-n100
  ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  clan-destiny = {
    nginx.nixos-proxy-cache.enable = true;
  };

  networking.useDHCP = true;

  nixpkgs.hostPlatform = lib.mkForce "x86_64-linux";

}
