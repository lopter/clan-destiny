{ pkgs, ... }:
{
  boot.kernelModules = [
    "r8125"
  ];

  environment.systemPackages = [
    pkgs.linuxKernel.packages.linux_6_15.r8125
  ];
}
