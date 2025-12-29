{ ... }:
{
  flake.nixosModules = {
    acl-watcher = ./acl-watcher.nix;
    avahi = ./avahi.nix;
    backups = ./backups.nix;
    base-pkgs = ./base-pkgs.nix;
    certbot-vault = ./certbot-vault.nix;
    certbot-vault-agent = ./certbot-vault-agent.nix;
    containers = ./containers.nix;
    fonts = ./fonts.nix;
    hass-pam-authenticate = ./hass-pam-authenticate.nix;
    home-kal = ./home-kal.nix;
    kde = ./kde.nix;
    lanzaboote = ./lanzaboote.nix;
    load-zfs-keys = ./load-zfs-keys.nix;
    linux = ./linux.nix;
    monfree = ./monfree.nix;
    nginx = ./nginx.nix;
    nginx-nixos-proxy-cache = ./nginx-nixos-proxy-cache.nix;
    nix-settings = ./nix-settings.nix;
    nixpkgs = ./nixpkgs.nix;
    postfix-relay = ./postfix-relay.nix;
    r8125 = ./r8125.nix;
    remote-builder = ./remote-builder.nix;
    shared = ./shared.nix;
    ssh = ./ssh.nix;
    starrs-gate = ./starrs-gate.nix;
    syncthing = ./syncthing.nix;
    typed-tags = ./typed-tags.nix;
    unbound = ./unbound.nix;
    usergroups = ./usergroups.nix;
    vault = ./vault.nix;
  };
}
