{ self, config, lib, pkgs, ... }:
let
  destiny-core' = self.inputs.destiny-core.packages.${builtins.currentSystem};
in
{
  options.clan.clan-destiny.services.backups = with lib; with types; {
    jobsByName = mkOption {
      description = mdDoc ''
        The list of backup jobs, the name of each backup job is used to look up
        public and private keys used with rsync jobs.
      '';
      type = attrsOf (submodule {
        options = {
          type = mkOption {
            description = mdDoc "The backup method used by this job.";
            type = enum [ "restic-b2" "rsync" ];
          };
          direction = mkOption {
            description = mdDoc ''
              Whether this backup is pushed or pulled from `localHost`. For
              `restic-b2` jobs only `push` is supported.
            '';
            type = enum [ "push" "pull" ];
          };
          localHost = mkOption {
            description = mdDoc "The FQDN of the local host";
            type = nonEmptyStr;
          };
          localPath = mkOption {
            description = mdDoc ''
              When `direction` is `pull` then this is the path where to store
              the backup at, otherwise it is the path to backup and send to
              `remoteHost`.
            '';
            type = path;
          };
          remoteHost = mkOption {
            description = mdDoc ''
              The FQDN of the remote host. This is only valid for `rsync` jobs.
            '';
            type = nullOr nonEmptyStr;
            default = null;
          };
          remotePath = mkOption {
            description = mdDoc ''
              When `direction` is `pull` then this is the path to backup on
              `remoteHost` otherwise this is the path where to store the
              backup at on `remoteHost`. This only valid for `rsync` jobs.
            '';
            type = nullOr nonEmptyStr;
            default = null;
          };
          oneFileSystem = mkEnableOption {
            description = mdDoc ''
              Do not cross filesystem boundaries, this is option is not honored
              and is always true with `rsync` jobs.
            '';
            default = true;
          };
          publicKeyPath = mkOption {
            description = mdDoc ''
              The SSH public key to be used with `rsync`. Unused for
              `restic-b2`.
            '';
            type = nullOr path;
            default = null;
          };
          privateKeyPath = mkOption {
            description = mdDoc ''
              The SSH private key to be used with `rsync`. Unused for
              `restic-b2`.
            '';
            type = nullOr path;
            default = null;
          };
          passwordPath = mkOption {
            description = mdDoc ''
              The password file to be used with `restic-b2`. Unused for
              `rsync`.
            '';
            type = nullOr path;
            default = null;
          };
          retention = mkOption {
            description = mdDoc ''
              How long to keep backup history for. This only used with
              `restic-b2` jobs. `rsync` jobs do not keep different versions.

              Retention is applied when a new backup is sucessfully made, that
              is, the last backups are kept indefinitely when no new backups
              are being made.
            '';
            type = nullOr nonEmptyStr;
            default = null;
          };
        };
      });
    };
    restic = {
      cacheDir = mkOption {
        description = mdDoc ''
          Path to a cache directory that can be used by restic.
        '';
        type = path;
      };
      b2 = {
        bucket = mkOption {
          description = mdDoc "B2 bucket where backups are stored.";
          type = nonEmptyStr;
        };
        keyIdPath = mkOption {
          description = mdDoc "Key ID to access the B2 api";
          type = path;
        };
        applicationKeyPath = mkOption {
          description = mdDoc "Application key to access the B2 api";
          type = path;
        };
      };
    };
  };

  config =
  let
    cfg = config.clan.clan-destiny.services.backups;
    vars = config.clan.core.vars.generators.clan-destiny-backups;
    fqdn = "${config.networking.hostName}.${config.networking.domain}";
    mkBackupSecrets = jobName: details:
      if details.type == "b2" then
        {
          prompts."${jobName}-password".createFile = true;
        }
      else
        throw "Backup type ${details.type} not supported";
    varGenerators = builtins.mapAttrs mkBackupSecrets cfg.jobsByName;
    # notNull = jobName: details: details != null;
    setPathsFromVars = jobName: details:
      if details.type == "b2" then
        {
          ${jobName}.passwordPath = vars.files."${jobName}-password".path;
        }
      else
        throw "Backup type ${details.type} not supported";
  in {
    clan.core.vars.generators.clan-destiny-backups = varGenerators;
    # clan.core.vars.generators.clan-destiny-backups = lib.filterAttrs notNull varGenerators;
    clan.clan-destiny.services.backups = builtins.mapAttrs setPathsFromVars cfg.jobsByName;
    environment.etc."clan-destiny-backups.json" = {
      text = builtins.toJSON cfg;
    };
    environment.systemPackages = with pkgs; [
      restic
      rsync
      destiny-core'.backups
    ];
    systemd.tmpfiles.rules = [
      "d ${cfg.restic.cacheDir} 0700 root root - -"
    ];
    systemd.timers."clan-destiny-backups" = {
      description = "Start clan-destiny-backups.service regularly";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnActiveSec = "12h";
        OnUnitActiveSec = "1d";
        Unit = "clan-destiny-backups.service";
      };
    };
    systemd.services."clan-destiny-backups" = {
      description = "Run local backup jobs defined in the config.";
      path = [ destiny-core'.backups ];
      onFailure = [ "clan-destiny-backups-notify-fail.service" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${destiny-core'.backups}/bin/clan-destiny-backups-dump run";
        Nice = 10;
        IOSchedulingPriority = 7;
      };
    };
    systemd.services."clan-destiny-backups-notify-fail" = {
      description = "Send an email to root when the backups fail to run.";
      path = with pkgs; [ mailutils ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "clan-destiny-backups-notify-fail" ''
          mail -s 'clan-destiny-backups-dump failed to run on ${config.networking.hostName}' root <<EOF
          systemctl status clan-destiny-backups.service:

          $(systemctl status clan-destiny-backups.service)

          -- 
          clan-destiny-backups-notify-fail running on ${config.networking.hostName}
          EOF
        '';
      };
    };
  };
}
