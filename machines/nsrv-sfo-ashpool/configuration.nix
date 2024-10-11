{ self, config, ... }:
let
in
{
  # users.users.user = {
  #   name = "kal";
  #   isNormalUser = true;
  #   extraGroups = [
  #     "wheel"
  #     "networkmanager"
  #     "video"
  #     "input"
  #   ];
  #   uid = 1000;
  #   openssh.authorizedKeys.keys = config.users.users.root.openssh.authorizedKeys.keys;
  # };

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Zerotier needs one controller to accept new nodes. Once accepted
  # the controller can be offline and routing still works.
  clan.core.networking.zerotier.controller.enable = false;

  clan.clan-destiny.services = {
    certbot-vault.enable = true;
    nginx.nixos-proxy-cache.enable = true;
    vault-server.enable = true;
    vault-client.enable = true;
  };

  services = {
    gitolite.enable = true;
    tailscale.enable = true;
    unbound.enable = true;
  };
}
