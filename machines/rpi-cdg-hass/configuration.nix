{ config, lib, self, ... }:
let
  inherit (config.lib.clan-destiny) ports typed-tags usergroups;

  lanInterfaces = [
    "end0"
  ];

  hassDir = "/stash/volumes/hass";
in
{
  clan-destiny.typed-tags.interfacesByRole = {
    lan = lanInterfaces;
  };

  networking.firewall.interfaces = typed-tags.repeatForInterfaces {
    allowedTCPPorts = [
      80
      443
    ];
  } lanInterfaces;

  services.home-assistant = {
      enable = true;
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
          longitude = 2.2107;
          latitude = 48.5124;
        };
        logger.default = "info";
        http.server_port = ports.homeAssistant;
        zha = { };
      };
  };
  services.nginx = {
    enable = true;
    virtualHosts = {
      "home-assistant-cdg.kalessin.fr" = {
        locations."/" = {
          proxyPass = "http://localhost:${toString ports.homeAssistant}";
        };
      };
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
}
