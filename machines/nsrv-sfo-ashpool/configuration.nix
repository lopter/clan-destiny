{ self, config, lib, ... }:
let
  inherit (config.lib.clan-destiny) ports usergroups;

  hassDir = "/stash/volumes/hass";
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
    usergroups.createNormalUsers = true;
    vault-server.enable = true;
    vault-client.enable = true;
  };

  services = {
    gitolite.enable = true;
    mpd.enable = true;
    tailscale.enable = true;
    unbound.enable = true;
  };

  networking.useDHCP = true;
  networking.networkmanager.unmanaged = [ "interface-name:ve-*" ];

  users = with usergroups.users.hass; {
    groups.hass.gid = lib.mkForce gid;
    users.hass = {
      uid = lib.mkForce uid;
      group = "hass";
      home = lib.mkForce hassDir;
      createHome = true;
      isSystemUser = true;
    };
  };

  containers.home-assistant =
  let
    macvlans = config.clan-destiny.typed-tags.interfacesByRole.lan;
  in
  {
    inherit macvlans;
    ephemeral = true;
    autoStart = true;
    bindMounts = {
      ${hassDir} = {
        hostPath = hassDir;
        isReadOnly = false;
      };
      "/dev/ttyUSB0" = {
        hostPath = "/dev/serial/by-id/usb-ITead_Sonoff_Zigbee_3.0_USB_Dongle_Plus_b6a3139cc145ed118f1bcf8f0a86e0b4-if00-port0";
        isReadOnly = false;
      };
    };
    allowedDevices = [
      {
        node = "/dev/serial/by-id/usb-ITead_Sonoff_Zigbee_3.0_USB_Dongle_Plus_b6a3139cc145ed118f1bcf8f0a86e0b4-if00-port0";
        modifier = "rw";
      }
    ];
    config =
    { config, pkgs, ... }:
    {
      services.home-assistant = {
        enable = true;
        extraComponents = [
          "default_config"
          "lifx"
          "zha"
        ];
        configDir = hassDir;
        config = {
          default_config = { };
          frontend = { };
          homeassistant = {
            unit_system = "metric";
            time_zone = "America/Los_Angeles";
            name = "SFO";
            longitude = -122.323219;
            latitude = 37.766574;
          };
          logger.default = "info";
          http.server_port = ports.homeAssistant;
          zha = { };
        };
      };

      networking = {
        firewall.enable = false;
        useNetworkd = true;
        useHostResolvConf = false;
      };

      systemd.network =
      let
        mkNetwork = ifname: {
          name = "40-mv-${ifname}";
          value = {
            matchConfig.Name = "mv-${ifname}";
            networkConfig.DHCP = "yes";
            dhcpV4Config.ClientIdentifier = "mac";
          };
        };
      in
      {
        enable = true;
        networks = builtins.listToAttrs (map mkNetwork macvlans);
      };

      users = with usergroups.users.hass; {
        groups.hass.gid = lib.mkForce gid;
        users.hass = {
          uid = lib.mkForce uid;
          group = "hass";
          home = lib.mkForce hassDir;
          isSystemUser = true;
        };
      };
    };
  };
}
