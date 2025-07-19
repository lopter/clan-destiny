{
  self,
  ...
}:
let
  enableSecureBoot = false;
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
}
