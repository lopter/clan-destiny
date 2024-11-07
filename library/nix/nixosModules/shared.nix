{ self, lib, config, clan-core, ... }:
let
  inherit (self.inputs) destiny-config home-manager;
  
  hostName = config.networking.hostName;
  hostDetails = config.clan-destiny.typed-tags.knownHosts.${hostName};
in
{
  imports = [
    # Enables the OpenSSH server for remote access
    clan-core.clanModules.sshd

    clan-core.clanModules.root-password
    clan-core.clanModules.state-version

    home-manager.nixosModules.home-manager

    self.nixosModules.acl-watcher
    self.nixosModules.backups
    self.nixosModules.base-pkgs
    self.nixosModules.certbot-vault
    self.nixosModules.linux
    self.nixosModules.nginx
    self.nixosModules.nginx-nixos-proxy-cache
    self.nixosModules.nix-settings
    self.nixosModules.postfix-relay
    self.nixosModules.ssh
    self.nixosModules.typed-tags
    self.nixosModules.usergroups
    self.nixosModules.vault
  ];

  options.clan-destiny.nixpkgs.unfreePredicates = lib.mkOption {
    description = ''
      The list of unfree package names that are allowed for installation.
    '';
    type = lib.types.listOf lib.types.nonEmptyStr;
    default = [ ];
  };

  config = {
    # Set this for clan commands use ssh i.e. `clan machines update`
    # If you change the hostname, you need to update this line to root@<new-hostname>
    # This only works however if you have avahi running on your admin machine else use IP
    clan.core.networking.targetHost = "root@${hostDetails.endPoint}";

    i18n.defaultLocale = "en_US.UTF-8";

    lib.clan-destiny.zoneFromHostname = self.lib.zoneFromHostname;

    nixpkgs.config.allowUnfreePredicate =
      let
        unfreePredicates = config.clan-destiny.nixpkgs.unfreePredicates;
      in
        pkg: builtins.elem (lib.getName pkg) unfreePredicates;

    powerManagement.powertop.enable = true;
    powerManagement.cpuFreqGovernor = lib.mkDefault "ondemand";

    # Locale service discovery and mDNS
    services.avahi.enable = true;

    networking.domain = "clandestiny.org";
    networking.firewall.enable = true;

    time.timeZone = "UTC";
  };
}
