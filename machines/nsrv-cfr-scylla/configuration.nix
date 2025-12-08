{ lib, ... }:
{
  boot.kernelModules = [ "nct6775" ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  clan-destiny = {
    nginx.nixos-proxy-cache.enable = true;
  };

  hardware.fancontrol.enable = true;
  hardware.fancontrol.config = ''
    INTERVAL=10
    DEVPATH=hwmon1=devices/platform/coretemp.0 hwmon0=devices/platform/nct6775.656
    DEVNAME=hwmon1=coretemp hwmon0=nct6776
    FCTEMPS= hwmon0/pwm2=hwmon1/temp1_input
    FCFANS=hwmon0/pwm1=hwmon0/fan1_input  hwmon0/pwm2=hwmon0/fan1_input
    MINTEMP= hwmon0/pwm2=55
    MAXTEMP= hwmon0/pwm2=75
    MINSTART= hwmon0/pwm2=200
    MINSTOP= hwmon0/pwm2=0
    MAXPWM=hwmon0/pwm2=255
  '';

  # ZFS uses `hostId` to identify to which machine a pool belongs to:
  networking.hostId = "031cfef3";
  networking.useDHCP = true;

  nixpkgs.hostPlatform = lib.mkForce "x86_64-linux";

  services.tailscale.enable = true;

}
