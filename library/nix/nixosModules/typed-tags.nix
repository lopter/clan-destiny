{ config, lib, ... }:
let
  cfg = config.clan-destiny.typed-tags;
in
{
  options.clan-destiny.typed-tags.knownHosts = lib.mkOption {
    description = ''
      Static registry of hosts we manage and some metadata about them.
    '';
    type = lib.types.attrsOf (
      lib.types.submodule {
        options = {
          hostNames = lib.mkOption {
            description = "Like `program.ssh.hostNames`.";
            type = lib.types.listOf lib.types.nonEmptyStr;
          };
          sshPubKey = lib.mkOption {
            description = "For OpenSSH.";
            type = lib.types.nonEmptyStr;
          };
          endPoint = lib.mkOption {
            description = "The IP address or hostname to connect to over SSH.";
            type = lib.types.nonEmptyStr;
          };
          hostKeyCheck = lib.mkOption {
            description = "How do we want to check the host's key over SSH.";
            type = lib.types.enum [
              "NONE"
              "STRICT"
            ];
            default = "STRICT";
          };
        };
      }
    );
    default = { };
  };
  options.clan-destiny.typed-tags.knownSshKeys = lib.mkOption {
    type = lib.types.attrsOf lib.types.nonEmptyStr;
    description = ''
      Known SSH Keys that can be referenced through the configuration.
    '';
    default = { };
  };
  options.clan-destiny.typed-tags.interfaceRoles = lib.mkOption {
    description = ''
      A list of roles you can use to categorize your network interfaces.
    '';
    example = [
      "lan"
      "wan"
      "tailnet-foo-bar"
    ];
    type = lib.types.listOf lib.types.nonEmptyStr;
    default = [ ];
  };
  options.clan-destiny.typed-tags.interfacesByRole =
    let
      option =
        role:
        lib.mkOption {
          description = ''
            The list of network interfaces attached to the role "${role}".
          '';
          type = lib.types.listOf lib.types.nonEmptyStr;
          default = [ ];
        };
      mkPair = role: {
        name = role;
        value = option role;
      };
    in
    builtins.listToAttrs (builtins.map mkPair cfg.interfaceRoles);

  config.lib.clan-destiny.typed-tags.repeatForInterfaces =
    interfaceCfg: interfacesLists:
    let
      mkPair = ifname: {
        name = ifname;
        value = interfaceCfg;
      };
    in
    builtins.listToAttrs (builtins.map mkPair (lib.flatten interfacesLists));
}

# {
#   config.clan.core.vars.generators.typed-tags = {
#     files.ssh-public-key = {
#       deploy = false;
#       secret = false;
#     };
#     prompts.ssh-public-key = {
#       createFile = true;
#       description = ''
#         The SSH public key of the host. Get it with:
#
#         ```sh
#         clan secrets get <machine>-ssh.id_ed25519 | ssh-keygen -y -f /dev/stdin
#         ```
#       '';
#     };
#   };
# }
