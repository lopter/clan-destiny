{
  self,
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (pkgs.stdenv.hostPlatform) system isx86;
  inherit (config.lib.clan-destiny) ports usergroups;

  vaultFQDN = self.inputs.destiny-config.lib.vault.fqdn;

  destiny-core' = self.inputs.destiny-core.packages.${system};
  nixpkgs-unfree' = self.inputs.nixpkgs-unfree.legacyPackages.${system};
  vault =
  if isx86 then
    nixpkgs-unfree'.vault.overrideAttrs (_prev: { doCheck = false; })
  else
    lib.info
      "Using vault-bin instead of compiling vault since ${system} is not x86"
      nixpkgs-unfree'.vault-bin;

  serverCfg = config.clan-destiny.vault-server;
  clientCfg = config.clan-destiny.vault-client;
  snapshooterCfg = config.clan-destiny.vault-snapshooter;

  vars = config.clan.core.vars.generators.clan-destiny-vault;
  commonVars = config.clan.core.vars.generators.clan-destiny-vault-common;
  snapshooterVars = config.clan.core.vars.generators.clan-destiny-vault-snapshooter;

  clientEnvironment = {
    VAULT_ADDR =
      if serverCfg.enable then
        # If you are using Tailscale and try to connect to the local vault
        # through its (local) Tailscale IP, the iptables rules set in
        # `ts-input` by Tailscale will prevent you to do that, since the
        # traffic will arrive on the loopback interface instead of the
        # tailscale interface. We avoid getting blocked by this firewall
        # rule by trying to connect on the loopback address instead:
        lib.info (
          "Using 127.0.0.1 instead of ${vaultFQDN} in VAULT_ADDR " + "since we seem to be on the vault server"
        ) "https://127.0.0.1:${toString ports.vault}/"
      else
        config.lib.clan-destiny.vault.addr;
    VAULT_TLS_SERVER_NAME = vaultFQDN;
    VAULT_CACERT = commonVars.files.tlsCaCert.path;
    VAULT_CLIENT_TIMEOUT = "3";
  };
in
{
  options.clan-destiny.vault-server = {
    enable = lib.mkEnableOption "Configure and enable the vault-server";
    nodeId = lib.mkOption {
      description = "The identifier for the node in the Raft cluster.";
      type = lib.types.nonEmptyStr;
    };
  };
  options.clan-destiny.vault-client = {
    enable = lib.mkEnableOption ''
      Setup the TLS CA certificate used by Vault along with the right
      environment vars.
    '';
  };
  options.clan-destiny.vault-snapshooter = {
    enable = lib.mkEnableOption ''
      Setup a periodic job to take vault raft snapshots that can be backed-up.
    '';
    snapshotDir = lib.mkOption {
      description = "Save snapshots in this directory";
      type = lib.types.path;
      default = "/stash/volumes/vault-snapshots";
    };
  };

  config = lib.mkMerge [
    {
      assertions = [
        {
          assertion = !snapshooterCfg.enable || (serverCfg.enable && clientCfg.enable);
          message = "vault-snapshooter requires both server and client sides for vault to be enabled";
        }
      ];
    }

    (lib.mkIf (serverCfg.enable || clientCfg.enable) {
      services.vault.package = vault;
    })

    (lib.mkIf serverCfg.enable {
      clan.core.vars.generators.clan-destiny-vault = {
        files.tlsCertChain.owner = "vault";
        files.tlsKey.owner = "vault";
        prompts.tlsCertChain = {
          persist = true;
          description = ''
            The TLS server certificate used by Vault followed by the CA
            certificate.
          '';
          type = "multiline";
        };
        prompts.tlsKey = {
          persist = true;
          description = "The key for the TLS certificate used by Vault";
          type = "multiline";
        };
      };
      services.vault = {
        enable = true;
        storageBackend = "raft";
        storagePath = config.users.users.vault.home;
        storageConfig = ''
          node_id = "${serverCfg.nodeId}"
        '';
        tlsCertFile = vars.files.tlsCertChain.path;
        tlsKeyFile = vars.files.tlsKey.path;
        address = "[::]:${toString ports.vault}";
        listenerExtraConfig = ''
          cluster_address = "[::]:${toString ports.vault-cluster}"
        '';
        extraConfig = ''
          # Note: the binaries built by Nix do not support the UI:
          #
          #   <h1>Vault UI is not available in this binary.</h1>
          #   </div>
          #   <p>To get Vault UI do one of the following:</p>
          #   <ul>
          #   <li><a href="https://www.vaultproject.io/downloads.html">Download an official release</a></li>
          #   <li>Run <code>make bin</code> to create your own release binaries.
          #   <li>Run <code>make dev-ui</code> to create a development binary with the UI.
          #   </ul>
          #
          # Or we could also switch to OpenBao.
          #
          # ui = true
          cluster_addr = "https://${vaultFQDN}:${toString ports.vault-cluster}"
          api_addr = "https://${vaultFQDN}:${toString ports.vault}"
          disable_mlock = true
        '';
      };
    })

    (lib.mkIf snapshooterCfg.enable {
      clan.core.vars.generators.clan-destiny-vault-snapshooter = {
        files.vaultRoleId.owner = "vault-snapshooter";
        files.vaultSecretId.owner = "vault-snapshooter";
        prompts.vaultRoleId = {
          persist = true;
          description = "The Vault Role ID to save raft snapshot for Vault";
          type = "hidden";
        };
        prompts.vaultSecretId = {
          persist = true;
          description = "The Vault Secret ID to save raft snapshot for Vault";
          type = "hidden";
        };
      };
      systemd.services.vault-snapshooter = {
        environment = clientEnvironment;
        serviceConfig = {
          ExecCondition = "${lib.getExe' pkgs.systemd "systemctl"} --quiet is-active vault.service";
          Type = "oneshot";
          User = "vault-snapshooter";
          Group = "vault-snapshooter";
        };
        path = [
          vault
          pkgs.jq
        ];
        script = # bash
        ''
          set -euo pipefail

          BACKUP_PATH=${lib.escapeShellArg (snapshooterCfg.snapshotDir + "/vault.snap")}

          ${lib.concatMapAttrsStringSep "\n" (k: v: "export ${k}") clientEnvironment}

          VAULT_TOKEN="$(
            vault write -format=json auth/approle/login \
              role_id=@${snapshooterVars.files.vaultRoleId.path} \
              secret_id=@${snapshooterVars.files.vaultSecretId.path} \
              | jq -r ".auth.client_token"
          )"
          export VAULT_TOKEN

          vault operator raft snapshot save "$BACKUP_PATH"
        '';
      };
      systemd.timers.vault-snapshooter = {
        description = "Start vault-snapshooter.service regularly";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnActiveSec = "30m";
          OnUnitActiveSec = "1h";
          Unit = "vault-snapshooter.service";
        };
      };
      systemd.tmpfiles.rules = [
        "d ${snapshooterCfg.snapshotDir} 0700 vault-snapshooter vault-snapshooter -"
      ];
      users = with usergroups.users.vault-snapshooter; {
        groups.vault-snapshooter = { inherit gid; };
        users.vault-snapshooter = {
          inherit uid;
          group = "vault-snapshooter";
          createHome = false;
          isSystemUser = true;
        };
      };
    })

    (lib.mkIf clientCfg.enable {
      clan-destiny.nixpkgs.unfreePredicates = [ "vault" "vault-bin" ];
      environment.variables = clientEnvironment;
      environment.systemPackages = [
        destiny-core'.vault-shell
        vault
      ];
      systemd.tmpfiles.rules = [
        "r! %h/.vault-token - - - - -"
      ];
      clan.core.vars.generators.clan-destiny-vault-common = {
        files.tlsCaCert.secret = false;
        prompts.tlsCaCert = {
          persist = true;
          description = "The TLS Certificate Authority certificate used by Vault";
          type = "multiline";
        };
        share = true;
      };
    })
  ];
}
