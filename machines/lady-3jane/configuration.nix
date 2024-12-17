{
  lib,
  self,
  clan-core,
  ...
}:
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

  boot.loader.efi.canTouchEfiVariables = true;
  # Secure boot using lanzaboote (replaces `boot.loader.systemd-boot`):
  boot.lanzaboote.enable = true;

  clan-destiny = {
    usergroups.createNormalUsers = true;
    vault-client.enable = true;
  };
  clan.user-password.user = "kal";

  services = {
    tailscale.enable = true;
    fwupd.enable = true;
  };
}
