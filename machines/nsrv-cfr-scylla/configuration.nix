{ config, lib, self, ... }:
let
  inherit (config.lib.clan-destiny) ports;
in
{
  boot.kernelModules = [ "nct6775" ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  clan-destiny = {
    nginx.nixos-proxy-cache = {
      enable = true;
      resolver.addresses = [ "127.0.0.1:${toString ports.unbound}" ];
    };
  };

  hardware.fancontrol.enable = true;
  hardware.fancontrol.config = ''
    INTERVAL=10
    DEVPATH=hwmon0=devices/platform/coretemp.0 hwmon1=devices/platform/nct6775.656
    DEVNAME=hwmon0=coretemp hwmon1=nct6776
    FCTEMPS= hwmon1/pwm2=hwmon0/temp1_input
    FCFANS=hwmon1/pwm1=hwmon1/fan1_input  hwmon1/pwm2=hwmon1/fan1_input
    MINTEMP= hwmon1/pwm2=55
    MAXTEMP= hwmon1/pwm2=75
    MINSTART= hwmon1/pwm2=200
    MINSTOP= hwmon1/pwm2=0
    MAXPWM=hwmon1/pwm2=255
  '';

  networking.useDHCP = true;

  # ZFS uses `hostId` to identify to which machine a pool belongs to:
  networking.hostId = "031cfef3";

  nixpkgs.hostPlatform = lib.mkForce "x86_64-linux";

  services = {
    unbound.enable = true;
  };

}
