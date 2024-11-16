{ self, config, lib, pkgs, ... }:
let
  inherit (config.networking) hostName;
  inherit (config.nixpkgs.hostPlatform) system;
  destiny-core' = self.inputs.destiny-core.packages.${system};
in
{
  options.clan-destiny.backups = with lib; with types; {
    jobsByName = mkOption {
      description = mdDoc ''
        The list of backup jobs, the name of each backup job is used to look up
        public and private keys used with rsync jobs.
      '';
      default = {};
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
      };
    };
  };

  config =
  let
    cfg = config.clan-destiny.backups;
    vars = config.clan.core.vars.generators.clan-destiny-backups;
    fqdn = with config.networking; "${hostName}.${domain}";
    allJobs = builtins.attrValues cfg.jobsByName;
    allJobTypes = builtins.map (details: details.type) allJobs;
    hasB2Jobs = builtins.foldl' (acc: type: acc && (type == "restic-b2")) true allJobTypes;
    mkBackupSecrets = jobsByName:
      let
        jobSecrets = builtins.attrValues (builtins.mapAttrs mkJobSecrets jobsByName);
        resticDetails = lib.optionalAttrs hasB2Jobs {
          prompts."restic-b2-key-id" = {
            createFile = true;
            description = "Key ID to access the B2 api";
          };
          prompts."restic-b2-application-key" = {
            createFile = true;
            description = "Application key to access the B2 api";
          };
        };
        op = acc: secrets: lib.recursiveUpdate acc secrets;
      in
        builtins.foldl' op { } (jobSecrets ++ [ resticDetails ]);
    mkJobSecrets = jobName: details:
      if details.type == "restic-b2" then
        lib.optionalAttrs (fqdn == details.localHost) {
          prompts."${jobName}-password".createFile = true;
        }
      else
        throw "Backup type ${details.type} not supported";
    # notNull = jobName: details: details != null;
    configToJson = jobsByName:
    let
      jobSecrets = builtins.mapAttrs hydrateWithVarsPaths jobsByName; 
      resticDetails = lib.optionalAttrs hasB2Jobs {
        restic.cacheDir = cfg.restic.cacheDir;
        restic.b2.bucket = cfg.restic.b2.bucket;
        restic.b2.keyIdPath = vars.files."restic-b2-key-id".path;
        restic.b2.applicationKeyPath = vars.files."restic-b2-application-key".path;
      };
    in
      { jobsByName = jobSecrets; } // resticDetails;
    hydrateWithVarsPaths = jobName: details:
      if details.type == "restic-b2" then
          details // (lib.optionalAttrs (fqdn == details.localHost) {
            passwordPath = vars.files."${jobName}-password".path;
          })
      /*
      else if details.type == "rsync" then
        # Do it based on direction and host
        details // {
          publicKeyPath = vars.files."${jobName}-public-key-path".path;
          privateKeyPath = vars.files."${jobName}-private-key-path".path;
        }
      */
      else
        throw "Backup type ${details.type} not supported";
  in {
    clan.core.vars.generators.clan-destiny-backups = mkBackupSecrets cfg.jobsByName;
    # clan.core.vars.generators.clan-destiny-backups = lib.filterAttrs notNull varGenerators;
    environment.etc."clan-destiny-backups.json" = {
      text = builtins.toJSON (configToJson cfg.jobsByName);
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
          mail -s 'clan-destiny-backups-dump failed to run on ${hostName}' root <<EOF
          systemctl status clan-destiny-backups.service:

          $(systemctl status clan-destiny-backups.service)

          -- 
            clan-destiny-backups-notify-fail running on ${hostName}
          EOF
        '';
      };
    };
  };
}
