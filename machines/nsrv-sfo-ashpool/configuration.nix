{ self, config, ... }:
let
  inherit (config.lib.clan-destiny) ports;
in
{
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  clan.core.networking.zerotier.controller.enable = false;

  clan-destiny = {
    acl-watcher.enable = true; # TODO: see why it does not work
    certbot-vault.enable = true;
    nginx.nixos-proxy-cache = {
      enable = true;
      resolver.addresses = [ "127.0.0.1:${toString ports.unbound}" ];
    };
    vault-server.enable = true;
    vault-client.enable = true;
  };

  services = {
    mpd.enable = true;
    gitolite.enable = true;
    tailscale.enable = true;
    unbound.enable = true;
  };
}
