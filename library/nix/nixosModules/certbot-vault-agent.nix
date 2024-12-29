{ config, lib, ... }:
let
  certbotCfg = config.clan-destiny.certbot-vault;
  cfg = config.clan-destiny.certbot-vault-agents;

  agentModule = {
    options = {
      user = lib.mkOption {
        description = "Run the vault agent under this user.";
        default = "root";
        type = lib.types.nonEmptyStr;
      };
      group = lib.mkOption {
        description = "Run the vault agent under this group.";
        default = "root";
        type = lib.types.nonEmptyStr;
      };
      roleIdFilePath = lib.mkOption {
        description = ''
          Path to a file containing the vault AppRole role id used to
          authenticate with Vault.
        '';
        type = lib.types.path;
      };
      secretIdFilePath = lib.mkOption {
        description = ''
          Path to a file containing the vault AppRole secret id used to
          authenticate with Vault.
        '';
        type = lib.types.path;
      };
      certsDirectory = lib.mkOption {
        type = lib.types.path;
        description = ''
          Directory where TLS certificates are saved (one sub-directory per
          domain in `domains`).
        '';
      };
      domains = lib.mkOption {
        description = ''
          List of certificates maintained by certbot to pull from Vault.

          For each domain the following files are written to the
          `<certsDirectory>/<domain>` directory:

          - key.pem;
          - chain.pem.
        '';
        type = with lib.types; listOf str;
        default = [ ];
      };
    };
  };

  mkAgentConfig =
    name: agentCfg: with agentCfg; {
      inherit user group;
      inherit (config.services.vault) package;
      enable = builtins.length domains > 0;
      settings = {
        auto_auth = [
          {
            method = [
              {
                type = "approle";
                config = [
                  {
                    role_id_file_path = roleIdFilePath;
                    secret_id_file_path = secretIdFilePath;
                  }
                ];
              }
            ];
            sink = {
              file = {
                config = [
                  {
                    path = "/run/${name}-vault-agent/token";
                  }
                ];
              };
            };
          }
        ];
        cache = [
          {
            use_auto_auth_token = true;
          }
        ];
        listener = {
          unix = {
            address = "/run/${name}-vault-agent/socket";
            tls_disable = true;
          };
        };
        vault = [
          {
            address = certbotCfg.vaultAddr;
            ca_cert = certbotCfg.vaultTlsCaCert;
            tls_server_name = certbotCfg.vaultTlsServerName;
          }
        ];
        template =
          let
            mkTemplate = domain: field: {
              contents = ''
                {{ with secret "${certbotCfg.vaultMount}/${certbotCfg.vaultPath}/${domain}" }}
                {{ .Data.data.${field} }}
                {{ end }}
              '';
              perms = "0400";
              error_on_missing_key = true;
              backup = false;
              destination = "${certsDirectory}/${domain}/${field}.pem";
            };
            mkDomain = domain: [
              (mkTemplate domain "key")
              (mkTemplate domain "chain")
            ];
          in
          builtins.concatMap mkDomain domains;
      };
    };
  mkAgentRunDirectory =
    name: agentCfg: with agentCfg; [
      "d /run/${name}-vault-agent 0700 ${user} ${group} - -"
      "d ${certsDirectory} 0700 ${user} ${group} - -"
    ];
in
{
  options.clan-destiny.certbot-vault-agents = lib.mkOption {
    default = { };
    description = ''
      Configure a vault-agent configured to pull the given TLS certificates
      from Vault and write them to disk.
    '';
    type = with lib.types; attrsOf (submodule agentModule);
  };

  config = {
    clan-destiny.vault-client.enable = lib.mkDefault ((builtins.length (builtins.attrNames cfg)) > 0);
    services.vault-agent.instances = builtins.mapAttrs mkAgentConfig cfg;
    systemd.tmpfiles.rules = lib.flatten (
      builtins.attrValues (builtins.mapAttrs mkAgentRunDirectory cfg)
    );
  };
}
