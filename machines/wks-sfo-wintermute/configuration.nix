{
  self,
  ...
}:
let
  inherit (self.inputs) destiny-config;

  enableSecureBoot = false;

  familyUserNames = builtins.attrNames destiny-config.lib.usergroups.familyUsers;
in
{
  imports = [
    self.nixosModules.home-kal
  ];

  # boot.kernelPackages = pkgs.linuxPackages_zen;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.systemd-boot.enable = !enableSecureBoot;
  boot.lanzaboote.enable = enableSecureBoot;

  clan-destiny = {
    usergroups.createNormalUsers = familyUserNames;
    vault-client.enable = true;
    remote-builder-server = {
      enable = true;
      clients = [
        "lady-3jane"
      ];
    };
  };

  networking.hostId = "edc840e0";

  services = {
    tailscale.enable = true;
    fwupd.enable = true;
  };
}
