{ config, lib, self, ... }:
let
  inherit (self.inputs.destiny-config.lib) usergroups;

  cfg = config.clan-destiny.containers;
in
{
  # This is option is for use by our `destiny-config` input. It's repeated from
  # the usergroups NixOS module, which uses vars and set user passwords, and is
  # meant to be used on the host-side, while this module is only imported in
  # containers.
  options.clan-destiny.usergroups = {
    createNormalUsers = lib.mkOption {
      type = with lib.types; listOf (enum (builtins.attrNames usergroups.familyUsers));
      description = ''
        Enable the creation of non-system users and groups defined in the
        destiny-config flake.
      '';
      default = [ ];
    };
  };

  options.clan-destiny.containers.macvlans = lib.mkOption {
    description = ''
      List of physical interfaces on the host that are going
      to be used to create MACVLAN interfaces in the container.

      This option is meant to be set on the container side.
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
