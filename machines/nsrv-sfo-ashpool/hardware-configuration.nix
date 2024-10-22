{ config, lib, ... }:
{
  boot.kernelModules = [ "kvm-intel" "wl" ];
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
  nixpkgs.hostPlatform = lib.mkForce "x86_64-linux";
}
