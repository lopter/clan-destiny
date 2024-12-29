{ config, lib, ... }:
let
  cfg = config.clan-destiny.containers;
in
{
  options.clan-destiny.containers.macvlans = lib.mkOption {
    description = ''
      List of physical interfaces on the host that are going
      to be used to create MACVLAN interfaces in the container.
    '';
    type = lib.types.listOf lib.types.str;
    default = [ ];
  };

  config = lib.mkIf (builtins.length cfg.macvlans > 0) {
    networking = {
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
        networks = builtins.listToAttrs (map mkNetwork cfg.macvlans);
      };
  };
}
