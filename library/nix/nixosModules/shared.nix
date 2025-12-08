{
  self,
  lib,
  config,
  clan-core,
  pkgs,
  ...
}:
let
  inherit (self.inputs) destiny-config home-manager;
  inherit (config.clan-destiny.typed-tags) knownHosts interfacesByRole;

  hostName = config.networking.hostName;
  hostDetails = knownHosts.${hostName};
in
{
  imports = [
    home-manager.nixosModules.home-manager

    self.nixosModules.acl-watcher
    self.nixosModules.avahi
    self.nixosModules.backups
    self.nixosModules.base-pkgs
    self.nixosModules.certbot-vault
    self.nixosModules.certbot-vault-agent
    self.nixosModules.hass-pam-authenticate
    self.nixosModules.lanzaboote
    self.nixosModules.linux
    self.nixosModules.monfree
    self.nixosModules.nginx
    self.nixosModules.nginx-nixos-proxy-cache
    self.nixosModules.nix-settings
    self.nixosModules.nixpkgs
    self.nixosModules.postfix-relay
    self.nixosModules.remote-builder
    self.nixosModules.ssh
    self.nixosModules.starrs-gate
    self.nixosModules.syncthing
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
          usesDefaultHostId = config.networking.hostId == "8425e349" && config.networking.hostName != "nsrv-cdg-jellicent";
        in
            !usesZFS || !usesDefaultHostId;
        message = "config.networking.hostId must be set when ZFS is in use";
      }
    ];

    clan.core = {
      # Set this for clan commands use ssh i.e. `clan machines update`
      # If you change the hostname, you need to update this line to root@<new-hostname>
      # This only works however if you have avahi running on your admin machine else use IP
      networking.targetHost = "root@${hostDetails.endPoint}";
      settings.state-version.enable = true;
    };

    i18n.defaultLocale = "en_US.UTF-8";

    lib.clan-destiny = {
      inherit (self.lib) zoneFromHostname;

      mkContainer =
      let
        macvlans = interfacesByRole.lan;
        defaultOptions = {
          inherit macvlans;
          ephemeral = true;
          autoStart = true;
          specialArgs = { inherit self; };
        };
      in
        containerConfig: defaultOptions // containerConfig // {
          config =
            { ... }:
            {
              imports = [
                containerConfig.config
                destiny-config.nixosModules.usergroups

                self.nixosModules.avahi
                self.nixosModules.containers
                self.nixosModules.base-pkgs
              ];
              clan-destiny.containers = { inherit macvlans; };
            };
        };
    };

    powerManagement = lib.mkIf pkgs.stdenv.hostPlatform.isx86 {
      powertop.enable = lib.mkDefault true;
      cpuFreqGovernor = lib.mkDefault "ondemand";
    };

    services.tailscale.disableTaildrop = true;

    networking.domain = "kalessin.fr";
    networking.firewall.enable = true;

    time.timeZone = "UTC";
  };
}
