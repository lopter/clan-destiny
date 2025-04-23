{ config, lib, ... }:
let
  certbotVaultCfg = config.clan-destiny.certbot-vault.vault;
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
      reloadCommand = lib.mkOption {
        description = ''
          Run this command whenever the certificate is updated on the disk.
        '';
        type = with lib.types; nullOr package;
        default = null;
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
            address = certbotVaultCfg.addr;
            ca_cert = certbotVaultCfg.tlsCaCert;
            tls_server_name = certbotVaultCfg.tlsServerName;
          }
        ];
        pid_file = "/run/${name}-vault-agent/pid";
        template =
          let
            mkTemplate = domain: field:
            {
              contents = ''
                {{ with secret "${certbotVaultCfg.mount}/${certbotVaultCfg.path}/${domain}" }}
                {{ .Data.data.${field} }}
                {{ end }}
              '';
              perms = "0400";
              error_on_missing_key = true;
              backup = false;
              destination = "${certsDirectory}/${domain}/${field}.pem";
            }
            // lib.optionalAttrs (reloadCommand != null) {
              exec.command = [ reloadCommand ];
            };
            mkDomain = domain: [
              (mkTemplate domain "key")
              (mkTemplate domain "chain")
            ];
          in
          builtins.concatMap mkDomain domains;
      };
    };
  mkAgentCertsDirectory =
    name: agentCfg: with agentCfg; [
      "d ${certsDirectory} 0700 ${user} ${group} - -"
    ];
  mkAgentRunDirectory =
    name: lib.nameValuePair
      "vault-agent-${name}"
      { serviceConfig.RuntimeDirectory = lib.mkForce "${name}-vault-agent"; };
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
    systemd.services = builtins.listToAttrs (map mkAgentRunDirectory (builtins.attrNames cfg));
    systemd.tmpfiles.rules = lib.flatten (
      builtins.attrValues (builtins.mapAttrs mkAgentCertsDirectory cfg)
    );
  };
}
