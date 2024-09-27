# Configure Postfix via `config.services.postfix` to relay all local mails to a
# remote SMTP server that requires authentication.
#
# This also setups the `mail` command.
#
# This module depends on other options you need to define, see NOTEs below.
{ config, lib, pkgs, ... }:
let
  cfg = config.multilab.simpleMTA;
in
{
  # NOTE: Set `domain`, `relayHost` and `relayPort` from your own module.
  options.multilab.simpleMTA = with lib; with types; {
    relayUsername = mkOption {
      description = mdDoc "The username to authenticate with the SMTP relay.";
      type = str;
    };
    relayPassword = mkOption {
      description = mdDoc ''
        The password to authenticate with the SMTP relay, e.g. a SOPS
        placeholder that will be substituted.
      '';
      type = str;
    };
    relayCredentialsPath = mkOption {
      description = mdDoc ''
        The path to the file where `relayCredentialsConfig` is written to,
        e.g. a SOPS template path.
      '';
      type = path;
    };
  };

  # NOTE: You must write this content at `relayCredentialsPath`:
  config.lib.multilab.simpleMTA.relayCredentialsConfig =
  let
    relayHost = config.services.postfix.relayHost;
    relayPort = config.services.postfix.relayPort;
    relayUsername = cfg.relayUsername;
    relayPassword = cfg.relayPassword;
  in
    "[${relayHost}]:${toString relayPort} ${relayUsername}:${relayPassword}";

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
    hostname = config.networking.fqdn;
    enable = true;
    mapFiles = {
      ${relayCredentialsFilename} = "${cfg.relayCredentialsPath}";
    };
    config = {
      smtpd_banner = "\$myhostname ESMTP \$mail_name";
      biff = false;

      # appending .domain is the MUA's job.
      append_dot_mydomain = false;

      readme_directory = false;

      # TLS parameters;
      smtpd_use_tls = false;
      smtp_use_tls = true;
      smtp_sasl_auth_enable = true;
      smtp_sasl_password_maps = "hash:/var/lib/postfix/conf/${relayCredentialsFilename}";
      smtp_sasl_security_options = "noanonymous";
      smtp_tls_session_cache_database = "btree:\${data_directory}/smtp_scache";
      smtp_tls_mandatory_protocols = "!SSLv2, !SSLv3, !TLSv1, !TLSv1.1";

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
