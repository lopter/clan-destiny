{ self, lib, ... }:
let
  inherit (self.inputs) nixos-hardware;
in
{
  imports = [
    nixos-hardware.nixosModules.raspberry-pi-4
  ];

  fileSystems."/" = {
    device = "/dev/disk/by-label/NIXOS_SD";
    fsType = "ext4";
  };

  # See https://github.com/nix-community/raspberry-pi-nix/issues/71#issuecomment-2391036704
  boot.initrd.systemd.tpm2.enable = false;

  nixpkgs.hostPlatform = lib.mkForce "aarch64-linux";
}
