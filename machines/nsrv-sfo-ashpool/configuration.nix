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

  services.getty.autologinUser = "root";

  systemd.network = {
    netdevs."20-br-lan".netdevConfig = {
      Kind = "bridge";
      Name = "br-lan";
    };
    networks."30-enp3s0f0" = {
      matchConfig.Name = "enp3s0f0";
      networkConfig.Bridge = "br-lan";
      linkConfig.RequiredForOnline = "enslaved";
    };
    networks."40-br-lan" = {
      matchConfig.Name = "br-lan";
      linkConfig.RequiredForOnline = "carrier";
      # linkConfig.RequiredForOnline = "routable";
      # DHCP not practical without a static MAC on the bridge.
      # networkConfig.DHCP = "yes";
      networkConfig = {
        Address = "172.28.53.6/24";
        Gateway = "172.28.53.1";
        DNS = [ "1.1.1.1" "8.8.8.8" ];
        IPv4Forwarding = true;
        IPv6Forwarding = true;
      };
    };
  };

  networking.useDHCP = lib.mkForce false;
  networking.networkmanager.unmanaged = [ "interface-name:ve-*" ];
  networking.firewall.checkReversePath = "loose";

  containers.test-pop = {
    enableTun = true;
    ephemeral = true;
    privateNetwork = true;
    hostBridge = "br-lan";
    localAddress = "172.28.53.20/24";
    config =
    { pkgs, ... }:
    {
      environment.systemPackages = with pkgs; [
        tcpdump
        mtr
      ];
      services.tailscale.enable = true;
      services.tailscale.extraUpFlags = [
        "--exit-node=100.97.86.75" "--exit-node-allow-lan-access=true"
      ];
      environment.etc."resolv.conf".text = ''
        nameserver 1.1.1.1
      '';
      networking.firewall.checkReversePath = "loose";
    };
  };

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

  containers.home-assistant = {
    enableTun = true;
    ephemeral = true;
    privateNetwork = true;
    hostBridge = "br-lan";
    localAddress = "172.28.53.21/24";
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

      networking.firewall.enable = false;

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
