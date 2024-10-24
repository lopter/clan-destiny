{ self, ... }:
{
  flake.nixosModules = {
    acl-watcher = ./acl-watcher.nix;
    base-pkgs = ./base-pkgs.nix;
    home-kal = ./home-kal.nix;
    kde = ./kde.nix;
    linux = ./linux.nix;
    nginx-nixos-proxy-cache = ./nginx-nixos-proxy-cache.nix;
    nix-settings = ./nix-settings.nix;
    shared = ./shared.nix;
    ssh = ./ssh.nix;
    typed-tags = ./typed-tags.nix;
    unbound = ./unbound.nix;
    usergroups = ./usergroups.nix;
  };
}
