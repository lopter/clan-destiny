{
  config,
  lib,
  self,
  pkgs,
  ...
}:
let
  inherit (self.inputs) destiny-config nixos-hardware;
  inherit (config.clan-destiny.typed-tags) knownHosts;

  enableSecureBoot = true;

  familyUserNames = builtins.attrNames destiny-config.lib.usergroups.familyUsers;
in
{
  imports = [
    nixos-hardware.nixosModules.lenovo-thinkpad-t480s

    self.nixosModules.home-kal
  ];

  nixpkgs.hostPlatform = lib.mkForce "x86_64-linux";

  boot.kernelPackages = pkgs.linuxPackages_zen;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.systemd-boot.enable = !enableSecureBoot;
  boot.lanzaboote.enable = enableSecureBoot;

  clan-destiny = {
    usergroups.createNormalUsers = familyUserNames;
    vault-client.enable = true;
    remote-builder-client = {
      enable = true;
      servers = {
        wks-sfo-wintermute = {
          sshHostname = knownHosts.wks-sfo-wintermute.endPoint;
          systems = [ "x86_64-linux" ];
          supportedFeatures = [ "nixos-test" "benchmark" "big-parallel" "kvm" ];
          maxJobs = 32;
        };
      };
    };
  };

  services = {
    tailscale.enable = true;
    fwupd.enable = true;
  };
}
