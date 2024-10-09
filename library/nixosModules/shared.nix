{ self, lib, config, clan-core, ... }:
let
  inherit (self.inputs) destiny-config;
  
  hostName = config.networking.hostName;
  hostDetails = config.clan-destiny.typed-tags.knownHosts.${hostName};
in
{
  imports = [
    # Enables the OpenSSH server for remote access
    clan-core.clanModules.sshd

    # Set a root password
    clan-core.clanModules.root-password
    clan-core.clanModules.state-version

    # self.clanModules.backups
    self.clanModules.certbot-vault
    self.clanModules.nginx
    self.clanModules.postfix-relay
    self.clanModules.vault
    self.nixosModules.base-pkgs
    self.nixosModules.linux
    self.nixosModules.nginx-nixos-proxy-cache
    self.nixosModules.nix-settings
    self.nixosModules.ssh
    self.nixosModules.typed-tags
  ];

  # Set this for clan commands use ssh i.e. `clan machines update`
  # If you change the hostname, you need to update this line to root@<new-hostname>
  # This only works however if you have avahi running on your admin machine else use IP
  clan.core.networking.targetHost = "root@${hostDetails.endPoint}";

  i18n.defaultLocale = "en_US.UTF-8";

  powerManagement.powertop.enable = true;
  powerManagement.cpuFreqGovernor = lib.mkDefault "ondemand";

  # Locale service discovery and mDNS
  services.avahi.enable = true;

  networking.domain = "clandestiny.org";
  networking.firewall.enable = true;

  time.timeZone = "UTC";
}
