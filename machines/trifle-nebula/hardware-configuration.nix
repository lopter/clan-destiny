{ lib, pkgs, self, ... }:
let
  lanInterfaces = [ "enp6s0" ];
in
{
  imports = [
    self.nixosModules.r8125
  ];

  nixpkgs.hostPlatform = lib.mkForce "x86_64-linux";

  clan-destiny.typed-tags.interfacesByRole = {
    lan = lanInterfaces;
  };

  # Too many issues with USB management: if this gets turned on then the
  # monitors, mouse and keyboard basically stop working.
  powerManagement.powertop.enable = false;

  systemd.services.reset-usb-dac = {
    enable = true;
    wantedBy = [ "sleep.target" ];
    unitConfig = {
      Description = "Reset my USB DAC after suspend";
      After = "sleep.target";
    };
    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "reset-usb-dac" ''
        delay_s=3
        printf "Waiting for %d seconds\n" "$delay_s"
        ${lib.getExe' pkgs.coreutils "sleep"} "$delay_s"
        ${lib.getExe' pkgs.usbutils "usbreset"} 4852:0003
      '';
    };
  };
}
