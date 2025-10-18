{
  self,
  pkgs,
  ...
}:
let
  inherit (pkgs.stdenv.hostPlatform) system;
  enableSecureBoot = false;
in
{
  imports = [
    self.nixosModules.home-kal
  ];

  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.systemd-boot.enable = !enableSecureBoot;
  boot.lanzaboote.enable = enableSecureBoot;
  boot.binfmt.emulatedSystems = [ "aarch64-linux" ];

  clan-destiny = {
    usergroups.createNormalUsers = [ "kal" ];
  };

  environment.systemPackages = [
    self.inputs.nix-auth.packages.${system}.default
  ];

  services = {
    tailscale.enable = true;
    fwupd.enable = true;
  };
}
