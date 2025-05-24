{
  config,
  lib,
  self,
  ...
}:
let
  inherit (self.inputs) nixos-hardware;

  enableSecureBoot = true;
in
{
  imports = [
    nixos-hardware.nixosModules.lenovo-thinkpad-t480s

    self.nixosModules.home-kal
  ];

  nixpkgs.hostPlatform = lib.mkForce "x86_64-linux";

  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.systemd-boot.enable = !enableSecureBoot;
  boot.lanzaboote.enable = enableSecureBoot;

  clan-destiny = {
    usergroups.createNormalUsers = true;
    vault-client.enable = true;
  };

  services = {
    tailscale.enable = true;
    fwupd.enable = true;
  };
}
