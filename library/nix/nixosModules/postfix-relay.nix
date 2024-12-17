{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.clan-destiny.postfix-relay;
  vars = config.clan.core.vars.generators.postfix-relay;
in
{
  options.clan-destiny.postfix-relay = {
    domain = lib.mkOption {
      description = ''
        The value for the `domain` Postfix module option, it will also be used
        to generate the FQDN to use as the `hostname` module option.

        For example, if you mail the user root, any email sent to root will
        actually be sent to `root@<domain>` through the specified SMTPS relay.
      '';
      type = lib.types.nonEmptyStr;
    };
    relayHost = lib.mkOption {
      description = "The value for `services.postfix.relayHost`.";
      type = lib.types.nonEmptyStr;
    };
    relayPort = lib.mkOption {
      description = "The value for `services.postfix.relayHost`.";
      example = 587;
      type = lib.types.port;
    };
    relayUsername = lib.mkOption {
      description = ''
        Username used by Postifx for SASL authentication with the SMTPS relay.
      '';
      type = lib.types.nonEmptyStr;
    };
  };

  config.clan.core.vars.generators.postfix-relay = {
    files.credentials = { };
    prompts.password = {
      createFile = false;
      description = ''
        Password used by Postifx for SASL authentication with the SMTPS relay.
      '';
      type = "hidden";
    };
    script = ''
      printf "[%s]:%d %s:%s" \
        "${cfg.relayHost}" \
        "${toString cfg.relayPort}" \
        "${cfg.relayUsername}" \
        "$(cat "$prompts/password")" \
        > $out/credentials
    '';
    share = true;
  };

  config.environment = {
    etc."mailutils.conf".text = ''
      address {
        email-domain "${config.services.postfix.domain}";
      }
    '';
    systemPackages = [ pkgs.mailutils ];
  };

  config.services.postfix =
    let
      relayCredentialsFilename = "relayCredentials";
    in
    {
      inherit (cfg) domain;
      hostname = "${config.networking.hostName}.${cfg.domain}";
      enable = true;
      mapFiles = {
        ${relayCredentialsFilename} = vars.files.credentials.path;
      };
      relayHost = cfg.relayHost;
      relayPort = cfg.relayPort;
      config = {
        smtpd_banner = "\$myhostname ESMTP \$mail_name";
        biff = false;

        # appending .domain is the MUA's job.
        append_dot_mydomain = false;

        readme_directory = false;

        # TLS parameters;
        smtpd_use_tls = false;
        smtp_tls_security_level = "secure";
        smtp_tls_verify_cert_match = "nexthop";
        smtp_tls_session_cache_database = "btree:\${data_directory}/smtp_scache";
        smtp_tls_mandatory_protocols = "!SSLv2, !SSLv3, !TLSv1, !TLSv1.1";
        smtp_sasl_auth_enable = true;
        smtp_sasl_password_maps = "hash:/var/lib/postfix/conf/${relayCredentialsFilename}";
        smtp_sasl_security_options = "noanonymous";

        mydestination = "\$myhostname, localhost, localhost.\$mydomain";
        myorigin = "\$mydomain";
        relay_domains = "\$mydomain";
        mynetworks = "127.0.0.0/8 [::ffff:127.0.0.0]/104 [::1]/128";
        mailbox_size_limit = "0";
        recipient_delimiter = "+";
        inet_interfaces = "loopback-only";
      };
    };
}
