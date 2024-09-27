{ inputs, self, ... }:
let
  inherit (inputs) nixos-hardware;
in
{
  imports = [
    nixos-hardware.nixosModules.lenovo-thinkpad-t480s
    self.nixosModules.homeKal
  ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Set this for clan commands use ssh i.e. `clan machines update`
  # If you change the hostname, you need to update this line to root@<new-hostname>
  # This only works however if you have avahi running on your admin machine else use IP
  clan.core.networking.targetHost = "root@lady-3jane.lightsd.io";

  multilab.usergroups.createNormalUsers = true;
  multilab.machine.enableFirewall = true;

  system.stateVersion = "24.11";

}
