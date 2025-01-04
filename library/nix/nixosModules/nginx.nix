# Set some common Nginx options and integrates with the certbot-vault-gandi
# module by adding a vault-agent sidecar to pull TLS certificates from Vault.
{ config, lib, ... }:
let
  cfg = config.clan-destiny.nginx;
  vars = config.clan.core.vars.generators.clan-destiny-nginx;

  hasCertbotDomains = builtins.length cfg.certbotDomains > 0;

  nginxHome = config.users.users.${nginxUser}.home;
  nginxUser = config.services.nginx.user;
  nginxGroup = config.services.nginx.group;

  proxyTimeout = "3s";
in
{
  options.clan-destiny.nginx = {
    enable = lib.mkEnableOption "Configure and enable nginx";
    certsDirectory = lib.mkOption {
      type = lib.types.path;
      default = "${nginxHome}/certs";
      description = ''
        Directory where TLS certificates are saved (one sub-directory per
        domain in `certbotDomains`).
      '';
    };
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

  config = lib.mkIf cfg.enable {
    clan.core.vars.generators.clan-destiny-nginx = lib.mkIf hasCertbotDomains {
      prompts.vaultRoleId = {
        createFile = true;
        description = "The Vault Role ID for certbot-vault";
        type = "hidden";
      };
      prompts.vaultSecretId = {
        createFile = true;
        description = "The Vault Secret ID for certbot-vault";
        type = "hidden";
      };
    };

    clan-destiny.certbot-vault-agents.nginx = lib.mkIf hasCertbotDomains {
      roleIdFilePath = vars.files.vaultRoleId.path;
      secretIdFilePath = vars.files.vaultSecretId.path;
      domains = cfg.certbotDomains;
      certsDirectory = cfg.certsDirectory;
      user = nginxUser;
      group = nginxGroup;
    };

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
            (lib.concatStringsSep "/" [
              cfg.certsDirectory
              domain
              "chain.pem"
            ])
            (lib.concatStringsSep "/" [
              cfg.certsDirectory
              domain
              "key.pem"
            ])
          ];
        in
        lib.lists.flatten (map mkPair cfg.certbotDomains);
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
  };
}
