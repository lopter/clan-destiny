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

  cfg = config.clan-destiny.certbot-vault;
  vars = config.clan.core.vars.generators.clan-destiny-certbot-vault;

  certbotPlugins =
    pythonPackages: with pythonPackages; [
      certbot-dns-ovh
      (callPackage (destiny-core + "/third_party/pypi/certbot-plugin-gandi.nix") { })
      (callPackage (destiny-core + "/third_party/pypi/certbot-vault.nix") { })
    ];
  certbotWithPlugins = pkgs.python3Packages.certbot.withPlugins certbotPlugins;
  certbot = pkgs.writeShellScriptBin "certbot" ''
    . ${vars.files.vaultCredentials.path}

    exec ${certbotWithPlugins}/bin/certbot \
        --config-dir ${cfg.configDir} \
        --logs-dir ${cfg.logDir} \
        --work-dir ${cfg.workDir} \
        --config ${pkgs.writeText "certbot.ini" cfg.configINI} \
        --agree-tos \
        --email ${cfg.email} \
        --installer vault \
        --vault-addr ${cfg.vault.addr} \
        --vault-mount ${cfg.vault.mount} \
        --vault-path ${cfg.vault.path} \
        ${
          lib.optionalString (
            builtins.stringLength cfg.vault.tlsServerName > 0
          ) "--vault-tls-server-name ${cfg.vault.tlsServerName}"
        } \
        ${
          lib.optionalString (
            builtins.stringLength cfg.vault.tlsCaCert > 0
          ) "--vault-tls-cacert ${cfg.vault.tlsCaCert}"
        } \
        "$@"
  '';

  instanceModule = {
    options = {
      authenticator = lib.mkOption {
        description = "The type of authenticator to use with this instance of certbot";
        type = lib.types.enum [
          "dns-gandi"
          "dns-ovh"
        ];
        default = null;
      };
      domains = lib.mkOption {
        description = "The list of domains to renew with this instance of certbot";
        type = with lib.types; listOf nonEmptyStr;
        default = [ ];
      };
    };
  };

  mkCertbotScript = name: config:
  let
    inherit (config) authenticator;
    credentialsFile = vars.files."${name}-credentials".path;
    cases = {
      dns-gandi = [
        "--authenticator dns-gandi"
        "--dns-gandi-credentials ${credentialsFile}"
      ];
      dns-ovh = [
        "--dns-ovh"
        "--dns-ovh-credentials ${credentialsFile}"
      ];
    };
    flags =
      if cases ? ${authenticator} then
        cases.${authenticator}
      else
        throw "certbot-vault: cannot build certbot script for ${name}: unknown authenticator type `${authenticator}' (expected one of: ${lib.concatStringsSep ", " (builtins.attrNames cases)})";
  in
    pkgs.writeShellScriptBin "certbot-${name}" ''
      ${certbot}/bin/certbot \
        ${lib.concatStringsSep " \\\n  " flags} \
        "$@"

      exit $?
    '';
  certbotScripts = builtins.mapAttrs mkCertbotScript cfg.instances;
in
{
  options.clan-destiny.certbot-vault = {
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
        `--log-dir` option for certbot, it will be created with the following
        `systemd.tmpfiles` rule:

            "d ''${logDir} 0750 certbot certbot 180d -"
      '';
      type = lib.types.path;
      default = "/var/log/certbot";
    };
    instances = lib.mkOption {
      description = ''
        Configure different instances of certbot with a specific authentication
        scheme, and a list of domains to automatically renew.

        For each instance a certbot wrapper script will be created to set the
        correct certbot flags. You will be asked to set the needed secrets
        through the `vars` subsystem.

        Each script will be named `certbot-''${name}` with the `name` of each
        instance.
      '';
      type = with lib.types; attrsOf (submodule instanceModule);
      default = { };
    };
    vault = {
      addr = lib.mkOption {
        description = "`--vault-addr` option for certbot.";
        type = lib.types.str;
      };
      mount = lib.mkOption {
        description = "`--vault-mount` option for certbot.";
        type = lib.types.str;
      };
      path = lib.mkOption {
        description = "`--vault-path` option for certbot.";
        type = lib.types.str;
      };
      tlsServerName = lib.mkOption {
        description = "`--vault-tls-server-name` option for certbot.";
        type = lib.types.str;
        default = "";
      };
      tlsCaCert = lib.mkOption {
        description = "`--vault-tls-cacert` option for certbot.";
        type = lib.types.str;
        default = "";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    clan.core.vars.generators.clan-destiny-certbot-vault =
    let
      # ovhApiEndpoints = [ "ovh-eu" "ovh-us" "ovh-ca" ];
      mkPrompts = acc: name: instanceCfg:
      let
        inherit (instanceCfg) authenticator;
        mkPrompt = description: {
          inherit description;
          persist = false;
          type = "hidden";
        };
        cases = {
          dns-gandi = [
            {
              name = "${name}-token";
              value = mkPrompt "Your Gandi API token for the certbot instance ${name}";
            }
          ];
          dns-ovh = [
            /*
              {
                name = "${name}-endpoint";
                value = {
                  description = "The OVH API endpoint to use (must be one of: ${lib.concatStringsSep ", " ovhApiEndpoints})";
                  persist = false;
                  type = "line";
                };
              }
            */
            {
              name = "${name}-application-key";
              value = mkPrompt "Your OVH API application key for the certbot instance ${name}";
            }
            {
              name = "${name}-application-secret";
              value = mkPrompt "Your OVH API application secret for the certbot instance ${name}";
            }
            {
              name = "${name}-consumer-key";
              value = mkPrompt "Your OVH API consumer key for the certbot instance ${name}";
            }
          ];
        };
      in
        if cases ? ${authenticator} then
          acc ++ cases.${authenticator}
        else
          throw "certbot-vault: cannot build vars prompts for ${name}: unknown authenticator type `${authenticator}' (expected one of: ${lib.concatStringsSep ", " (builtins.attrNames cases)})";
      prompts = builtins.listToAttrs (lib.foldlAttrs mkPrompts [ ] cfg.instances);
      mkFiles = acc: name: acc // { "${name}-credentials".owner = "certbot"; };
      files = builtins.foldl' mkFiles { } (builtins.attrNames cfg.instances);
      mkScriptParts = acc: name: instanceCfg:
      let
        inherit (instanceCfg) authenticator;
        cases = {
          dns-gandi = ''
            printf "dns_gandi_token=%s\n" "$(cat "$prompts/${name}-token")" >"$out/${name}-credentials"
          '';
          dns-ovh = ''
            cat >"$out/${name}-credentials" <<EOF
            dns_ovh_endpoint = ovh-eu
            dns_ovh_application_key = $(cat "$prompts/${name}-application-key")
            dns_ovh_application_secret = $(cat "$prompts/${name}-application-secret")
            dns_ovh_consumer_key = $(cat "$prompts/${name}-consumer-key")
            EOF
          '';
        };
      in
        if cases ? ${authenticator} then
          acc ++ [ cases.${authenticator} ]
        else
          throw "certbot-vault: cannot build vars script for ${name}: unknown authenticator type `${authenticator}' (expected one of: ${lib.concatStringsSep ", " (builtins.attrNames cases)})";
      scriptParts = lib.foldlAttrs mkScriptParts [ ] cfg.instances;
    in
    {
      files = files // { vaultCredentials.owner = "certbot"; };
      prompts = prompts // {
        VaultRoleID = {
          persist = false;
          description = "The Vault Role ID for certbot-vault";
          type = "hidden";
        };
       VaultSecretId = {
          persist = false;
          description = "The Vault Secret ID for certbot-vault";
          type = "hidden";
        };
      };
      script = (lib.concatLines scriptParts) + ''
        printf "export VAULT_ROLE_ID=$(cat "$prompts/VaultRoleID")\n" >> $out/vaultCredentials
        printf "export VAULT_SECRET_ID=$(cat "$prompts/VaultSecretId")\n" >> $out/vaultCredentials
      '';
    };

    environment.systemPackages = [ certbot ] ++ (builtins.attrValues certbotScripts);

    # We need to call certbot renew for each instance.
    # There is two ways to approach this with systemd:
    #
    # 1. Use one timer and one service unit per certbot instance ;
    # 2. Use one timer for all instance and a target to group multiple
    #    service units together, this actually gets pretty complex, see:
    #    - original question: https://serverfault.com/q/776437
    #    - this insightful comment: https://serverfault.com/a/1128671
    #
    # Having multiple timers seems simpler, so we are going with that. We could
    # also be using systemd templates, but it seems easier to do the templating
    # in Nix (see https://github.com/NixOS/nixpkgs/pull/186314/).

    systemd.timers =
    let
      mkTimer = acc: name: instanceCfg:
        acc ++ (lib.optional (builtins.length instanceCfg.domains > 0) {
          name = "certbot-${name}-renew";
          value = {
            description = "Run `certbot-${name} renew` regularly";
            wantedBy = [ "timers.target" ];
            timerConfig = {
              OnCalendar = "*-*-1,18"; # twice a month
              RandomizedDelaySec = 60 * 60 * 24; # anytime during our OnCalendar days
              Unit = "certbot-${name}-renew.service";
            };
          };
      });
    in
      builtins.listToAttrs (lib.foldlAttrs mkTimer [ ] cfg.instances);

    systemd.services =
    let
      mkService = acc: name: instanceCfg:
      let
        inherit (instanceCfg) domains;
        certbotWrapper = certbotScripts.${name};
      in
        acc ++ (lib.optionals (builtins.length domains > 0) [
          {
            name = "certbot-${name}-renew";
            value = {
              description = "Renew certificates issued with Let's Encrypt using `certbot-${name}`";
              path = [ certbotWrapper ];
              onFailure = [ "certbot-${name}-notify-fail.service" ];
              serviceConfig = {
                Type = "oneshot";
                ExecStart = pkgs.writeShellScript "certbot-${name}-renew" ''
                  ${certbotWrapper}/bin/certbot-${name} renew \
                    -d ${lib.concatStringsSep " \\\n  -d " (map lib.escapeShellArg domains)}

                  exit $?
                '';
                User = "certbot";
                Group = "certbot";
              };
            };
          }
          {
            name = "certbot-${name}-notify-fail";
            value = {
              description = "Send an email to root when certbot-vault fails to run";
              path = [ pkgs.mailutils ];
              serviceConfig = {
                Type = "oneshot";
                ExecStart = pkgs.writeShellScript "certbot-${name}-notify-fail" ''
                  mail -s 'certbot-${name} renew failed to run on ${config.networking.hostName}' root <<EOF
                  systemctl status certbot-${name}-renew.service:

                  $(systemctl status certbot-${name}-renew.service)

                  -- 
                  certbot-${name}-notify-fail running on ${config.networking.hostName}
                  EOF
                '';
              };
            };
          }
        ]);
    in
      builtins.listToAttrs (lib.foldlAttrs mkService [ ] cfg.instances);

    systemd.tmpfiles.rules = [
      "d ${cfg.logDir} 0750 certbot certbot 180d -"
    ];

    users.groups.certbot = lib.mkDefault { };
    users.users.certbot = lib.mkDefault {
      home = "/var/lib/certbot";
      createHome = true;
      isSystemUser = true;
      description = "Certbot ACME agent";
      group = "certbot";
      # It would be better to set packages here instead of in
      # environment.systemPackages but this attrset gets overwritten in
      # destiny-config…
    };
  };
}
