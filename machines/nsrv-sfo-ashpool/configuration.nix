{ config, lib, ... }:
let
  inherit (config.lib.clan-destiny) ports usergroups;

  hassDir = "/stash/volumes/hass";
  hassUser = with usergroups.users.hass; {
    groups.hass.gid = lib.mkForce gid;
    users.hass = {
      uid = lib.mkForce uid;
      group = "hass";
      home = lib.mkForce hassDir;
      createHome = true;
      isSystemUser = true;
    };
  };

  familyUserNames = builtins.attrNames usergroups.familyUsers;
in
{
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  clan.core.networking.zerotier.controller.enable = false;

  clan-destiny = {
    acl-watcher.enable = false; # TODO: see why it does not work
    certbot-vault.enable = true;
    nginx.nixos-proxy-cache.enable = true;
    starrs-gate.enable = true;
    syncthing = {
      createUserSystemInstances = [
        "kal"
      ];
      containerHostnameSuffix = "ashpool";
    };
    usergroups.createNormalUsers = familyUserNames;
    vault-server.enable = true;
    vault-client.enable = true;
  };

  services = {
    gitolite.enable = true;
    mpd.enable = true;
    tailscale.enable = true;
  };

  networking.useDHCP = true;

  users = hassUser;

  /*
  containers =
  let
    inherit (config.lib.clan-destiny) mkContainer;
  in
  {
    home-assistant = mkContainer {
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
        { ... }:
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

          users = hassUser;
        };
    };
  };
  */
}
