{ self, ... }:
{
  flake.nixosModules = {
    acl-watcher = ./acl-watcher.nix;
    backups = ./backups.nix;
    base-pkgs = ./base-pkgs.nix;
    certbot-vault = ./certbot-vault.nix;
    home-kal = ./home-kal.nix;
    kde = ./kde.nix;
    linux = ./linux.nix;
    nginx = ./nginx.nix;
    nginx-nixos-proxy-cache = ./nginx-nixos-proxy-cache.nix;
    nix-settings = ./nix-settings.nix;
    postfix-relay = ./postfix-relay.nix;
    shared = ./shared.nix;
    ssh = ./ssh.nix;
    typed-tags = ./typed-tags.nix;
    unbound = ./unbound.nix;
    usergroups = ./usergroups.nix;
    vault = ./vault.nix;
  };
}
