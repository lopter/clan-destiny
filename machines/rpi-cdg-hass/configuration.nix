{ config, lib, pkgs, self, ... }:
let
  inherit (config.lib.clan-destiny) ports typed-tags usergroups;
  inherit (pkgs.stdenv.hostPlatform) system;
  inherit (self.inputs) destiny-core;

  lanInterfaces = [
    "end0"
  ];

  hassDir = "/stash/volumes/hass";

  hass-pam-authenticate = destiny-core.packages.${system}.hass-pam-authenticate;
in
{
  clan-destiny = {
    nginx.enable = true;
    typed-tags.interfacesByRole = {
      lan = lanInterfaces;
      tailnet-lopter-github = [ config.services.tailscale.interfaceName ];
    };
    usergroups.createNormalUsers = true;
  };

  networking.firewall.interfaces =
  let
    inherit (config.clan-destiny.typed-tags) interfacesByRole;
  in
  lib.mergeAttrsList (lib.flatten [
    (
      typed-tags.repeatForInterfaces
        { allowedTCPPorts = [ 443 ]; }
        interfacesByRole.lan
    )
    (
      typed-tags.repeatForInterfaces
        { allowedTCPPorts = [ 80 ]; }
        interfacesByRole.tailnet-lopter-github
    )
  ]);

  services.home-assistant = { # some bits are in destiny-config
      enable = true;
      extraPackages =  [
        hass-pam-authenticate
      ];
      extraComponents = [
        "default_config"
        "zha"
      ];
      configDir = hassDir;
      config = {
        default_config = { };
        frontend = { };
        homeassistant = {
          unit_system = "metric";
          time_zone = "Europe/Paris";
          name = "CDG";
          longitude = 2.350699;
          latitude = 48.852737;
          auth_providers = [
            {
              type = "homeassistant";
            }
            {
              type = "command_line";
              command = "${hass-pam-authenticate}/bin/hass-pam-authenticate";
              args = [ "client" ];
              meta = true;
            }
          ];
        };
        logger.default = "info";
        http = {
          server_port = ports.homeAssistant;
          use_x_forwarded_for = true;
        };
        zha = { };
      };
  };
  # Nginx virtual hosts are configured from destiny-config.
  services.nginx.appendHttpConfig = ''
    proxy_buffering off;
  '';
  services.tailscale.enable = true;

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
}
