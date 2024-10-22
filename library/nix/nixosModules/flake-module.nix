{ self, ... }:
{
  flake.nixosModules = {
    acl-watcher = ./acl-watcher.nix;
    base-pkgs = ./base-pkgs.nix;
    linux = ./linux.nix;
    nginx-nixos-proxy-cache = ./nginx-nixos-proxy-cache.nix;
    nix-settings = ./nix-settings.nix;
    shared = ./shared.nix;
    ssh = ./ssh.nix;
    typed-tags = ./typed-tags.nix;
    unbound = ./unbound.nix;
  };
}
