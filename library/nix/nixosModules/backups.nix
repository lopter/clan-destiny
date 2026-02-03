{
  self,
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (config.networking) hostName;
  inherit (pkgs.stdenv.hostPlatform) system;
  destiny-core' = self.inputs.destiny-core.packages.${system};
in
{
  options.clan-destiny.backups =
    with lib;
    with types;
    {
      jobsByName = mkOption {
        description = ''
          The list of backup jobs, the name of each backup job is used to look up
          public and private keys used with rsync jobs.
        '';
        default = { };
        type = attrsOf (submodule {
          options = {
            type = mkOption {
              description = "The backup method used by this job.";
              type = enum [
                "restic-b2"
                "rsync"
              ];
            };
            direction = mkOption {
              description = ''
                Whether this backup is pushed or pulled from `localHost`. For
                `restic-b2` jobs only `push` is supported.
              '';
              type = enum [
                "push"
                "pull"
              ];
            };
            localHost = mkOption {
              description = "The FQDN of the local host";
              type = nonEmptyStr;
            };
            localPath = mkOption {
              description = ''
                When `direction` is `pull` then this is the path where to store
                the backup at, otherwise it is the path to backup and send to
                `remoteHost`.
              '';
              type = path;
            };
            remoteHost = mkOption {
              description = ''
                The FQDN of the remote host. This is only valid for `rsync` jobs.
              '';
              type = nullOr nonEmptyStr;
              default = null;
            };
            remotePath = mkOption {
              description = ''
                When `direction` is `pull` then this is the path to backup on
                `remoteHost` otherwise this is the path where to store the
                backup at on `remoteHost`. This only valid for `rsync` jobs.
              '';
              type = nullOr nonEmptyStr;
              default = null;
            };
            oneFileSystem = mkOption {
              description = ''
                Do not cross filesystem boundaries, this is option is not honored
                and is always true with `rsync` jobs.
              '';
              type = bool;
              default = true;
            };
            retention = mkOption {
              description = ''
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
          description = ''
            Path to a cache directory that can be used by restic.
          '';
          type = path;
        };
        b2 = {
          bucket = mkOption {
            description = "B2 bucket where backups are stored.";
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
      isLocalJob = details: details.localHost == fqdn;
      localJobsByName = lib.filterAttrs (jobName: isLocalJob) cfg.jobsByName;
      isB2Job = details: details.type == "restic-b2";
      hasB2Jobs = builtins.any isB2Job (builtins.attrValues localJobsByName);
    in
    # TODO: always write the config and then merge that with the conditional
      # creation of the systemd stuff
    lib.mkIf (builtins.length (builtins.attrNames localJobsByName) > 0) {
      clan.core.vars.generators.clan-destiny-backups =
        let
          mkJobSecrets =
            jobName: details:
            lib.optionalAttrs (isB2Job details) {
              prompts."${jobName}-password".persist = true;
            };
          jobSecrets = lib.pipe localJobsByName [
            (builtins.mapAttrs mkJobSecrets)
            builtins.attrValues
            (builtins.filter (details: details != { }))
          ];
          resticDetails = lib.optionalAttrs hasB2Jobs {
            prompts."restic-b2-key-id" = {
              persist = true;
              description = "Key ID to access the B2 api";
            };
            prompts."restic-b2-application-key" = {
              persist = true;
              description = "Application key to access the B2 api";
            };
          };
        in
          builtins.foldl' lib.recursiveUpdate { } (jobSecrets ++ [ resticDetails ]);
      environment.etc."clan-destiny-backups.json".source = pkgs.writeTextFile {
        name = "clan-destiny-backups.json";
        text =
          let
            hydrateWithVarsPaths =
              jobName: details:
                details // (lib.optionalAttrs (isB2Job details) {
                  passwordPath = vars.files."${jobName}-password".path;
                });
            jobsWithSecrets = builtins.mapAttrs hydrateWithVarsPaths localJobsByName;
            jobsByName = cfg.jobsByName // jobsWithSecrets;
            resticDetails = lib.optionalAttrs hasB2Jobs {
              restic.cacheDir = cfg.restic.cacheDir;
              restic.b2.bucket = cfg.restic.b2.bucket;
              restic.b2.keyIdPath = vars.files."restic-b2-key-id".path;
              restic.b2.applicationKeyPath = vars.files."restic-b2-application-key".path;
            };
          in
            builtins.toJSON ({ inherit jobsByName; } // resticDetails);
        checkPhase = ''
          ${destiny-core'.backups}/bin/clan-destiny-backups \
            --config-path "$out" \
            validate-config \
            --fqdn ${lib.escapeShellArg fqdn} \
            --ignore-missing-paths
        '';
      };
      environment.systemPackages = [ destiny-core'.backups ];
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
          ExecStart = "${destiny-core'.backups}/bin/clan-destiny-backups dump run";
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
