{ config, lib, pkgs, self, ... }:
let
  inherit (self.inputs.destiny-config.lib) usergroups;
  inherit (config.networking) hostName;

  userName = "nix-builder";

  serverCfg = config.clan-destiny.remote-builder-server;
  clientCfg = config.clan-destiny.remote-builder-client;
  varsGenerators = config.clan.core.vars.generators;

  varGenerator = {
    files = {
      publicKey.secret = false;
      privateKey = { };
    };
    runtimeInputs = [ pkgs.openssh ];
    script = ''
      ssh-keygen -t ed25519 -N "" -C "" -f $out/key
      mv $out/key $out/privateKey
      mv $out/key.pub $out/publicKey
    '';
    share = true;
  };
  mkGeneratorName = client: server: "clan-destiny-remote-builder-${client}-${server}";

  getPublicKeys = clients: lib.flip map clients (
    client: varsGenerators."${mkGeneratorName client hostName}".files.publicKey.value
  );

  mkSshHostMatchBlocks = servers: lib.flip builtins.mapAttrs servers (server: cfg: ''
    Host clan-destiny-remote-builder-${server}
      User nix-builder
      Hostname ${if cfg ? sshHostname then cfg.sshHostname else server}
      BatchMode yes
      IdentityFile ${varsGenerators."${mkGeneratorName hostName server}".files.privateKey.path}
  '');

  mkBuildMachines = servers: lib.flip map (lib.attrsToList servers) (pair: {
    inherit (pair.value) systems supportedFeatures maxJobs;
    protocol = "ssh-ng";
    hostName = "clan-destiny-remote-builder-${pair.name}";
  });
in
{
  options = {
    clan-destiny.remote-builder-client = {
      enable = lib.mkEnableOption "Enable remote nix builds on the given servers";
      servers = lib.mkOption {
        type = with lib.types; attrsOf (submodule {
          options = {
            sshHostname = lib.mkOption {
              type = with lib.types; nullOr nonEmptyStr;
              default = null;
            };
            systems = lib.mkOption {
              type = with lib.types; listOf nonEmptyStr;
            };
            supportedFeatures = lib.mkOption {
              type = with lib.types; listOf nonEmptyStr;
            };
            maxJobs = lib.mkOption {
              type = types.int;
              default = 1;
            };
          };
        });
        default = { };
      };
    };
    clan-destiny.remote-builder-server = {
      enable = lib.mkEnableOption "Allow the given clients to this machine as a remote builder";
      clients = lib.mkOption {
        type = with lib.types; listOf nonEmptyStr;
        default = [ ];
      };
    };
  };

  config = lib.mkMerge [
    (lib.mkIf serverCfg.enable {
      clan.core.vars.generators = lib.genAttrs' serverCfg.clients (client: {
          name = mkGeneratorName client hostName;
          value = varGenerator;
      });

      nix.settings.trusted-users = [ userName ];

      users = with usergroups.users.${userName}; {
        groups.nix-builder.gid = gid;
        users.nix-builder = {
          uid = uid;
          group = userName;
          isSystemUser = true;
          createHome = true;
          homeMode = "0500";
          openssh.authorizedKeys.keys = getPublicKeys serverCfg.clients;
          shell = pkgs.bash;
        };
      };
    })

    (lib.mkIf clientCfg.enable {
      clan.core.vars.generators = lib.mapAttrs' (server: _cfg: {
          name = mkGeneratorName hostName server;
          value = varGenerator;
      }) clientCfg.servers;

      nix.distributedBuilds = true;
      nix.buildMachines = mkBuildMachines clientCfg.servers;

      programs.ssh.extraConfig = builtins.concatStringsSep "\n" (
        builtins.attrValues (mkSshHostMatchBlocks clientCfg.servers)
      );

      systemd.tmpfiles.rules = [
        "d /run/nix-remote-builders 0750 root root - -"
      ];
    })
  ];
}
