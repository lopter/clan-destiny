# Configure certbot with Gandi for domain ownership verification and Vault to
# store certificates.
#
# This module assumes you defined a `certbot` user and group. There is also a
# couple files you'll need to setup with Gandi and Vault credentials, see
# options `vaultCredentialsFile` and `gandiCredentialsFile` below. I maintain
# those with sops-nix.
#
# To issue TLS certificates for a new domain login to the machine that runs
# this module, then:
#
# DOMAIN=example.com
# sudo -u certbot -- certbot-vault -d $DOMAIN
{ config, lib, pkgs, self, ... }:
let
  inherit (self.inputs) destiny-core;
  cfg = config.clan.clan-destiny.services.certbot-vault;
in
{
  options.clan.clan-destiny.services.certbot-vault = {
    enable = lib.mkEnableOption "Enable domain renewal with certbot";
    configDir = lib.mkOption {
      description = "`--config-dir` option for certbot.";
      type = lib.types.path;
    };
    workDir = lib.mkOption {
      description = ''
        `--workDir` option for certbot. Defaults
        to the value for the `configDir` option.
      '';
      type = lib.types.path;
      default = cfg.configDir;
    };
    configINI = lib.mkOption {
      description = ''
        Contents for the file passed to the `--config` option for certbot.
      '';
      type = lib.types.lines;
      default = ''
        agree-tos = true
        non-interactive = true
        keep-until-expiring = true
        key-type = ecdsa
        # NOTE(2023-12-21): ed25519 not yet supported, secp521r1
        #                   also an option see RFC 8446:
        elliptic-curve = secp384r1
      '';
    };
    email = lib.mkOption {
      description = "`--email` option for certbot.";
      type = lib.types.str;
    };
    logDir = lib.mkOption {
      description = ''
        `--log-dir` option for certbot, if `null` this defaults to
        `/var/log/certbot` managed with the following `systemd.tmpfiles` rule:

            "d ''${logDir} 0750 certbot certbot 180d -"
      '';
      type = lib.types.nullOr lib.types.path;
      default = "/var/log/certbot";
    };
    vaultAddr = lib.mkOption {
      description = "`--vault-addr` option for certbot.";
      type = lib.types.str;
    };
    vaultMount = lib.mkOption {
      description = "`--vault-mount` option for certbot.";
      type = lib.types.str;
    };
    vaultPath = lib.mkOption {
      description = "`--vault-path` option for certbot.";
      type = lib.types.str;
    };
  };

  config = 
  let
    certbotPlugins = certbotPythonPkgs: with pkgs.python3Packages; [
      (callPackage (destiny-core + "/third_party/pypi/certbot-plugin-gandi.nix") { })
      (callPackage (destiny-core + "/third_party/pypi/certbot-vault.nix") { })
    ];
    # TODO: wrap the original certbot binary with our arguments too.
    certbot = pkgs.python3Packages.certbot.withPlugins certbotPlugins;
    certbotConfigINI = pkgs.writeText "cli.ini" cfg.configINI;
    logDir = if cfg.logDir == null then "/var/log/certbot" else cfg.logDir;
    certbotVaultScript = pkgs.writeShellScriptBin "certbot-vault" ''
        . ${vars.files.vaultCredentials.path}

        exec certbot \
            --config-dir ${cfg.configDir} \
            --logs-dir ${logDir} \
            --work-dir ${cfg.workDir} \
            --config ${certbotConfigINI} \
            --agree-tos \
            --email ${cfg.email} \
            --authenticator dns-gandi \
            --dns-gandi-credentials ${vars.files.gandiCredentials.path} \
            --installer vault \
            --vault-addr ${cfg.vaultAddr} \
            --vault-mount ${cfg.vaultMount} \
            --vault-path ${cfg.vaultPath} \
            "$@"
      '';
    certbotPkgs = [ certbot certbotVaultScript ];
    vars = config.clan.core.vars.generators.clan-destiny-certbot-vault;
  in lib.mkIf cfg.enable {
    clan.core.vars.generators.clan-destiny-certbot-vault = {
      files.vaultCredentials = { };
      files.gandiCredentials = { };
      prompts.VaultRoleID = {
        createFile = false;
        description = "The Vault Role ID for certbot-vault";
        type = "hidden";
      };
      prompts.VaultSecretId = {
        createFile = false;
        description = "The Vault Secret ID for certbot-vault";
        type = "hidden";
      };
      prompts.gandiToken = {
        createFile = false;
        description = "Your Gandi API token";
        type = "hidden";
      };
      script = ''
        printf "export VAULT_ROLE_ID=$(cat "$prompts/VaultRoleID")\n" >> $out/vaultCredentials
        printf "export VAULT_SECRET_ID=$(cat "$prompts/VaultSecretId")\n" >> $out/vaultCredentials

        printf "dns_gandi_token=$(cat "$prompts/gandiToken")\n" >> $out/gandiCredentials
      '';
    };
    systemd.timers."clan-destiny-certbot-renew" = {
      description = "Run `certbot-vault renew` regularly";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "*-*-1,18"; # twice a month
        RandomizedDelaySec = 60 * 60 * 24; # anytime during our OnCalendar days
        Unit = "clan-destiny-certbot-renew.service";
      };
    };
    systemd.services."clan-destiny-certbot-renew" = {
      description = "Renew certificates issued with Let's Encrypt using certbot";
      path = certbotPkgs;
      onFailure = [ "clan-destiny-certbot-notify-fail.service" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${certbotVaultScript}/bin/certbot-vault renew";
        User = "certbot";
        Group = "certbot";
      };
    };
    systemd.services."clan-destiny-certbot-notify-fail" = {
      description = "Send an email to root when certbot-vault fails to run";
      path = with pkgs; [ mailutils ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "clan-destiny-certbot-notify-fail" ''
          mail -s 'certbot-vault failed to run on ${config.networking.hostName}' root <<EOF
          systemctl status clan-destiny-certbot-renew.service:

          $(systemctl status clan-destiny-certbot-renew.service)

          -- 
          clan-destiny-certbot-notify-fail running on ${config.networking.hostName}
          EOF
        '';
      };
    };
    systemd.tmpfiles.rules = lib.mkIf (cfg.logDir == null) [
      "d ${logDir} 0750 certbot certbot 180d -"
    ];
    users.groups.certbot = lib.mkDefault { };
    users.users.certbot = lib.mkDefault {
      home = "/var/lib/certbot";
      createHome = true;
      isSystemUser = true;
      description = "Certbot ACME agent";
      group = "certbot";
    };
    environment.systemPackages = certbotPkgs;
  };
}
