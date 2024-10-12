# Set some common Nginx options and integrates with the certbot-vault-gandi
# module by adding a vault-agent sidecar to pull TLS certificates from Vault.
{ config, lib, ... }:
let
  cfg = config.clan.clan-destiny.services.nginx;
  vars = config.clan.core.vars.generators.clan-destiny-nginx;
  certbotCfg = config.clan.clan-destiny.services.certbot-vault;

  hasCertbotDomains = builtins.length cfg.vaultAgent.certbotDomains > 0;

  nginxHome = config.users.users.${nginxUser}.home;
  nginxUser = config.services.nginx.user;
  nginxGroup = config.services.nginx.group;

  proxyTimeout = "3s";
in
{
  options.clan.clan-destiny.services.nginx = {
    enable = lib.mkEnableOption "Configure and enable nginx";
    certsDirectory = lib.mkOption {
      type = lib.types.path;
      default = "${nginxHome}/certs";
      description = ''
        Directory where TLS certificates are saved (one sub-directory per
        domain in `certbotDomains`).
      '';
    };
    vaultAgent = {
      certbotDomains = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = ''
          List of certificates maintained by certbot to pull from Vault.

          For each domain the following files are written to the `certs/<domain>`
          directory within Nginx's home directory:

          - key.pem;
          - chain.pem.
        '';
      };
    };
  };

  config = lib.mkIf cfg.enable {
    clan.core.vars.generators.clan-destiny-nginx = {
      prompts.VaultRoleID = {
        createFile = true;
        description = "The Vault Role ID for certbot-vault";
        type = "hidden";
      };
      prompts.VaultSecretId = {
        createFile = true;
        description = "The Vault Secret ID for certbot-vault";
        type = "hidden";
      };
    };

    # TODO: do it on a per interface basis:
    networking.firewall.allowedTCPPorts = [ 80 443 ];

    users.users."${nginxUser}" = {
      home = nginxHome;
      createHome = true;
    };

    systemd.tmpfiles.rules = [
      "d /run/nginx-vault-agent 0700 ${nginxUser} ${nginxGroup} - -"
      "d ${cfg.certsDirectory} 0700 ${nginxUser} ${nginxGroup} - -"
    ];

    # This will reload nginx for each certificate update because I couldn't
    # think of an easy way to coalesce changes for multiple certificates, other
    # than using watchman, which feels heavy handed. I kinda feel that there
    # should be an option in systemd.path to wait some amount of time after a
    # change before activating the related unit. See also:
    #
    # - somewhat related: https://github.com/systemd/systemd/issues/20818
    #
    # Maybe that's not too hard to implement: you could store state on
    # `struct Path` and use the event loop to delay activation.
    systemd.paths.nginx-reload-certs = lib.mkIf hasCertbotDomains {
      pathConfig.PathChanged =
      let
        mkPair = domain: [
          (lib.concatStringsSep "/" [ cfg.certsDirectory domain "chain.pem" ])
          (lib.concatStringsSep "/" [ cfg.certsDirectory domain "key.pem" ])
        ];
      in
        lib.lists.flatten (map mkPair cfg.vaultAgent.certbotDomains);
      wantedBy = [ "nginx.service" ];
    };

    systemd.services.nginx-reload-certs = lib.mkIf hasCertbotDomains {
      description = "Send a SIGHUP to Nginx when TLS certificates are updated";
      serviceConfig = {
        Type = "oneshot";
        ExecCondition = "/run/current-system/systemd/bin/systemctl -q is-active nginx.service";
        ExecStart = "/run/current-system/systemd/bin/systemctl reload nginx.service";
      };
    };

    security.dhparams = {
      enable = true;
      params.nginx = { };
    };

    services.nginx = {
      enable = true;
      recommendedTlsSettings = true;
      recommendedOptimisation = true;
      recommendedGzipSettings = true;
      recommendedProxySettings = true;
      proxyTimeout = proxyTimeout;
      sslDhparam = config.security.dhparams.params.nginx.path;
    };

    services.vault-agent.instances.nginx = {
      enable = hasCertbotDomains;
      user = nginxUser;
      group = nginxGroup;
      settings = {
        auto_auth = [{
          method = [{
            type = "approle";
            config = [{
              role_id_file_path = vars.files.roleIdPath;
              secret_id_file_path = vars.files.secretIdPath;
            }];
          }];
          sink = {
            file = {
              config = [{
                path = "/run/nginx-vault-agent/token";
              }];
            };
          };
        }];
        cache = [{
          use_auto_auth_token = true;
        }];
        listener = {
          unix = {
            address = "/run/nginx-vault-agent/socket";
            tls_disable = true;
          };
        };
        vault = [{
          address = certbotCfg.vaultAddr;
        }];
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
            destination = "${cfg.certsDirectory}/${domain}/${field}.pem";
          };
          mkDomain = domain: [
            (mkTemplate domain "key")
            (mkTemplate domain "chain")
          ];
        in
          builtins.concatMap mkDomain cfg.vaultAgent.certbotDomains;
     };
    };
  };
}
