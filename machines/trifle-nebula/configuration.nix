{
  config,
  self,
  ...
}:
let
  inherit (config.clan-destiny) typed-tags;

  enableSecureBoot = false;
  syncthingPort = 22000;
in
{
  imports = [
    self.nixosModules.home-kal
  ];

  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.systemd-boot.enable = !enableSecureBoot;
  boot.lanzaboote.enable = enableSecureBoot;

  clan-destiny = {
    usergroups.createNormalUsers = [ "kal" ];
  };

  services = {
    tailscale.enable = true;
    fwupd.enable = true;
  };

  networking.firewall.interfaces = config.lib.clan-destiny.typed-tags.repeatForInterfaces {
    allowedTCPPorts = [
      syncthingPort
    ];
  } typed-tags.interfacesByRole.lan;
}
