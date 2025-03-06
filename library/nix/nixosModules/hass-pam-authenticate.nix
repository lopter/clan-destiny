{ config, lib, pkgs, self, ... }:
let
  inherit (config.lib.clan-destiny) usergroups;
  inherit (self.inputs) destiny-core;
  inherit (pkgs.stdenv.hostPlatform) system;

  package = destiny-core.packages.${system}.hass-pam-authenticate;
  hass-pam-authenticate = "${package}/bin/hass-pam-authenticate";

  socketPath = "/run/hass-pam-authenticate.sock";

  hassCfg = config.services.home-assistant;
  hass-auth-providers =
    if hassCfg.enable then
      lib.attrByPath [ "config" "homeassistant" "auth_providers" ] [ ] hassCfg
    else
      [ ];
  enable = builtins.any (provider: (provider.command or "") == hass-pam-authenticate) hass-auth-providers;

  cfg = config.clan-destiny.hass-pam-authenticate;
in
{
  options.clan-destiny.hass-pam-authenticate = {
    remoteUsers = lib.mkOption {
      type = with lib.types; listOf nonEmptyStr;
      default = [ ];
      description = "Set `local_only = false` for the listed users.";
    };
  };

  config = lib.mkIf enable {
    security.pam.services.hass-pam-authenticate.text = with pkgs; ''
      account required ${pam}/lib/security/pam_unix.so
      auth sufficient ${pam}/lib/security/pam_unix.so likeauth
      auth required ${pam}/lib/security/pam_deny.so
    '';

    systemd.services.hass-pam-authenticate = {
      description = "Privilege separated service to provide PAM authentication to home-assistant";
      wantedBy = [ "home-assistant.service" ];
      requires = [ "hass-pam-authenticate.socket" ];
      after = [ "hass-pam-authenticate.socket" ];
      serviceConfig = {
        ExecStart =
        let
          fmtRemoteUser = acc: name: acc ++ [ "--remote-user" (lib.escapeShellArg name) ];
          remoteUsers = builtins.foldl' fmtRemoteUser [ ] cfg.remoteUsers;
        in
          "${hass-pam-authenticate} server ${lib.concatStringsSep " " remoteUsers}";
        Restart = "on-failure";
        User = "hass-pam-authenticate";
        Group = "hass-pam-authenticate";
        SupplementaryGroups = [ "shadow" ];
        CapabilityBoundingSet = [
          "CAP_SETUID"
          "CAP_SETGID"
          "CAP_AUDIT_WRITE"
        ];
        LockPersonality = true;
        MemoryDenyWriteExecute = true;
        NoNewPrivileges = false;
        PrivateDevices = true;
        PrivateTmp = true;
        ProtectClock = true;
        ProtectControlGroups = "strict";
        ProtectHome = true;
        ProtectHostname = true;
        ProtectKernelLogs = true;
        ProtectKernelModules = true;
        ProtectKernelTunables = true;
        ProtectProc = "noaccess";
        ProtectSystem = "strict";
        RemoveIPC = true;
        RestrictAddressFamilies = [ "AF_NETLINK" "AF_UNIX" ];
        RestrictNamespaces = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        SystemCallArchitectures = "native";
        SystemCallFilter = [
          "@system-service"
          "@setuid"
        ];
      };
    };
    systemd.sockets.hass-pam-authenticate = {
      description = "Socket for hass-pam-authenticate";
      wantedBy = [ "pam-hass-authenticate.service" ];
      socketConfig = {
        ListenStream = socketPath;
        SocketMode = "0660";
        SocketUser = "hass-pam-authenticate";
        SocketGroup = "hass";
        Accept = "no";
      };
    };

    users = with usergroups.users.hass-pam-authenticate; {
      groups.hass-pam-authenticate.gid = gid;
      users.hass-pam-authenticate = {
        uid = uid;
        group = "hass-pam-authenticate";
        extraGroups = [ "shadow" ];
        createHome = false;
        isSystemUser = true;
      };
    };
  };
}
