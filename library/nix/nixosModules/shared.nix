{
  self,
  lib,
  config,
  clan-core,
  pkgs,
  ...
}:
let
  inherit (self.inputs) home-manager;

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
    self.nixosModules.certbot-vault-agent
    self.nixosModules.containers
    self.nixosModules.hass-pam-authenticate
    self.nixosModules.lanzaboote
    self.nixosModules.linux
    self.nixosModules.nginx
    self.nixosModules.nginx-nixos-proxy-cache
    self.nixosModules.nix-settings
    self.nixosModules.nixpkgs
    self.nixosModules.postfix-relay
    self.nixosModules.ssh
    self.nixosModules.starrs-gate
    self.nixosModules.typed-tags
    self.nixosModules.usergroups
    self.nixosModules.vault
  ];

  config = {
    assertions = [
      {
        assertion =
        let
          usesZFS = builtins.any (e: e.fsType == "zfs") (builtins.attrValues config.fileSystems);
          # The hostId from the installer leaked into jellicent, let's not have that again in the future:
          usesDefaultHostId = config.networking.hostId != "8425e349" && config.networking.hostName != "nsrv-cdg-jellicent";
        in
            !usesZFS || !usesDefaultHostId;
        message = "config.networking.hostId must be set when ZFS is in use";
      }
    ];

    # Set this for clan commands use ssh i.e. `clan machines update`
    # If you change the hostname, you need to update this line to root@<new-hostname>
    # This only works however if you have avahi running on your admin machine else use IP
    clan.core.networking.targetHost = "root@${hostDetails.endPoint}";

    i18n.defaultLocale = "en_US.UTF-8";

    lib.clan-destiny.zoneFromHostname = self.lib.zoneFromHostname;

    powerManagement = lib.mkIf pkgs.stdenv.hostPlatform.isx86 {
      powertop.enable = true;
      cpuFreqGovernor = lib.mkDefault "ondemand";
    };

    # Locale service discovery and mDNS
    services.avahi.enable = true;

    networking.domain = "kalessin.fr";
    networking.firewall.enable = true;

    time.timeZone = "UTC";
  };
}
