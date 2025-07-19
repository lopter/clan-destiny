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

  systemd.services.reset-usb-dac = {
    enable = true;
    wantedBy = [ "sleep.target" ];
    unitConfig = {
      Description = "Reset my USB DAC after suspend";
      After = "sleep.target";
    };
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = "yes";
      ExecStart = "${pkgs.usbutils}/bin/usbreset 4852:0003";
    };
  };
}
