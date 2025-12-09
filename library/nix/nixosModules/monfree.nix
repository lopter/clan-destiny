{
  config,
  lib,
  pkgs,
  self,
  utils,
  ...
}:
let
  inherit (self.inputs.destiny-config.lib) popAddresses;
  inherit (self.inputs.destiny-core.packages.${system}) monfree;
  inherit (pkgs.stdenv.hostPlatform) system;
  inherit (config.lib.clan-destiny) mkContainer typed-tags usergroups;
  inherit (config.clan-destiny.typed-tags) interfacesByRole;
  inherit (config.networking) hostName;

  intervalOption = lib.mkOption {
    description = ''
      The exporter will run mtr and will be scraped at this in interval
      (seconds).
    '';
    type = lib.types.int;
    default = 60;
  };
in
{
  options.clan-destiny.monfree = {
    exporter = {
      enable = lib.mkEnableOption "Enable mtr based monitoring service (exporter component)";
      endpoints = lib.mkOption {
        description = "The list of endpoints (IPv4/6) to monitor using `mtr`";
        type = with lib.types; nonEmptyListOf nonEmptyStr;
      };
      port = lib.mkOption {
        type = lib.types.port;
        default = 9091;
      };
      address = lib.mkOption {
        type = lib.types.nonEmptyStr;
        default = "0.0.0.0";
      };
      interval = intervalOption;
    };
    monitor = {
      enable = lib.mkEnableOption ''
        Start prometheus and Grafana. Prometheus will scrape the exporters,
        while Grafana serves as the UI.
      '';
      # I guess that's when clan services would be handy: the
      # list of exporters could be configured automatically.
      exporters = lib.mkOption {
        description = "The list of exporters to scrape formated as `addr:port`";
        type =  with lib.types; listOf nonEmptyStr;
        default = [ ];
      };
      guiVirtualHost = lib.mkOption {
        description = "The hostname/domain on which the web UI is exposed";
        type = lib.types.nonEmptyStr;
      };
      adminEmail = lib.mkOption {
        description = "Admin email for Grafana";
        type = with lib.types; nullOr nonEmptyStr;
      };
      interval = intervalOption;
    };
  };

  config =
  let
    cfgExporter = config.clan-destiny.monfree.exporter;
    cfgMonitor = config.clan-destiny.monfree.monitor;
    varsMonitor = config.clan.core.vars.generators.clan-destiny-monfree;

    exporterService = {
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        DynamicUser = true;
        Type = "exec";
        ExecStart = utils.escapeSystemdExecArgs ([
          (lib.getExe monfree) "exporter"
          "--listen-addr=${cfgExporter.address}"
          "--port=${toString cfgExporter.port}"
          "--interval=${toString cfgExporter.interval}"
        ] ++ map (endpoint: "--endpoint=${endpoint}") cfgExporter.endpoints);
        LockPersonality = true;
        MemoryDenyWriteExecute = true;
        NoNewPrivileges = true;
        PrivateDevices = true;
        PrivateTmp = true;
        PrivateMounts = true;
        # PrivateUsers = true;
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
        RestrictAddressFamilies = [ "AF_INET" "AF_INET6" ];
        RestrictNamespaces = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        SystemCallArchitectures = "native";
        SystemCallFilter = [
          "@system-service"
          "@network-io"
        ];
        AmbientCapabilities = [ "CAP_NET_RAW" ];
        CapabilityBoundingSet = [ "CAP_NET_RAW" ];
      };
    };

    grafanaAdminPasswordHostPath = "/run/monfree/secrets/grafana-admin-password";
    grafanaAdminPasswordContainerPath = "/run/secrets/grafana-admin-password";
    grafanaPort = config.services.grafana.settings.server.http_port;

    users = with usergroups.users; {
      groups.grafana.gid = lib.mkForce grafana.gid;
      groups.prometheus.gid = lib.mkForce prometheus.gid;
      users.grafana = {
        uid = lib.mkForce grafana.uid;
        isSystemUser = lib.mkForce true;
        group = "grafana";
      };
      users.prometheus = {
        uid = lib.mkForce prometheus.uid;
        isSystemUser = lib.mkForce true;
        group = "prometheus";
      };
    };
  in
  lib.mkMerge [
    (lib.mkIf (cfgExporter.enable || cfgMonitor.enable) { inherit users; })

    (lib.mkIf (cfgExporter.enable && !cfgMonitor.enable) {
      # To keep networking simple we run the exporter on the host directly (so
      # that it can be scraped via its addr/port) except if the host is also
      # gonna run the monitor component (which goes into a container) in which
      # case we put the exporter in the container too so that it can be scraped
      # via localhost since I am using macvlan interfaces in my containers which
      # makes it difficult to loop back to the host from a container.
      systemd.services.monfree-exporter = exporterService;
    })

    (lib.mkIf cfgMonitor.enable {
      clan.core.vars.generators.clan-destiny-monfree = {
        files.grafana-admin-password.owner = "grafana";
        prompts.grafana-admin-password = {
          description = "The admin password to provision in Grafana (leave empty for autogeneration)";
          type = "hidden";
          persist = true;
        };
        runtimeInputs = with pkgs; [
          coreutils
          gawk
          pwgen
        ];
        script = ''
          trim() {
            awk '{ gsub(/^[[:space:]]+|[[:space:]]+$/, ""); print }'
          }

          if [ -z "$(trim < "$prompts/grafana-admin-password" | tee "$out/grafana-admin-password")" ]; then
            pwgen -sy 24 1 | trim > "$out/grafana-admin-password"
          fi
        '';
      };

      # We need to copy the secret out of where sops put it for a couple reasons:
      #
      # 1. `sops-nix` symlinks `/run/secrets/` to an actual secret generation in
      #    `/run/secrets.d` but you can't idmap a file with a symlink in it;
      # 2. `ramfs` which `sops-nix` uses does not seem to support the `idmap`
      #    option.
      #
      # See: https://github.com/systemd/systemd/issues/38603.
      system.activationScripts.monfreeSetupSecrets =
        if config.sops.useSystemdActivation or false then
          builtins.throw "Please add support for `sops.useSystemdActivation`"
        else
          {
            deps = [
              "setupSecrets"
            ];
            text = # bash
            ''(
              src="${varsMonitor.files.grafana-admin-password.path}"
              dst="${grafanaAdminPasswordHostPath}"
              mount_point="$(dirname "$dst")"
              if [ "$NIXOS_ACTION" = "dry-activate" ]; then
                printf 'Would copy `%s` to `%s`\n' "$src" "$dst"
              else
                install -d -m 751 "$mount_point"
                eval $(findmnt --pairs --first --output TARGET "$mount_point")
                if [ -z "$TARGET" ]; then
                  mount -t tmpfs -o nosuid,nodev,noexec,relatime,mode=751 tmpfs "$mount_point"
                fi
                cp --preserve=all "$src" "$dst"
              fi
            )'';
          };

      # Using a container allows us to run a separate Prometheus instance for
      # which I don't care about backing up its data.
      containers.monfree = mkContainer {
        # We still want to keep the data across reboot and deploys and have an
        # opportunity to export our grafana dashboards, maybe declare them here.
        ephemeral = false;
        privateNetwork = true;
        privateUsers = "pick";
        additionalCapabilities  = [ "CAP_NET_RAW" ];
        bindMounts = {
          grafana-admin-password = {
            # See:
            # - https://www.freedesktop.org/software/systemd/man/latest/systemd-nspawn.html#--bind=
            # - https://github.com/NixOS/nixpkgs/issues/419007
            # - https://github.com/NixOS/nixpkgs/issues/329530#issuecomment-2513815925
            mountPoint = "${grafanaAdminPasswordContainerPath}:idmap";
            hostPath = grafanaAdminPasswordHostPath;
          };
        };
        config =
          { config, pkgs, ... }:
          {
            inherit users;

            imports = [
              self.inputs.destiny-config.nixosModules.tailscale # TODO: make public
              self.nixosModules.typed-tags
            ];

            clan-destiny.tailscale.interfaces = map (ifname: "mv-${ifname}") interfacesByRole.lan;

            systemd.services.monfree-exporter = lib.mkIf cfgExporter.enable exporterService;

            services.prometheus = {
              enable = true;
              listenAddress = "127.0.0.1";
              globalConfig.scrape_interval = "${toString cfgMonitor.interval}s";
              scrapeConfigs = [
                {
                  job_name = "monfree";
                  static_configs = [{ targets = cfgMonitor.exporters; }];
                }
              ];
            };

            services.grafana = {
              enable = true;
              provision = {
                enable = true;
                datasources.settings = {
                  prune = false;
                  datasources = [{
                    name = "Prometheus";
                    type = "prometheus";
                    url = "http://127.0.0.1:${toString config.services.prometheus.port}";
                    jsonData = {
                      timeInterval = "${toString cfgMonitor.interval}s";
                      prometheusType = "Prometheus";
                      prometheusVersion = pkgs.prometheus.version;
                    };
                  }];
                };
              };
              settings = {
                server = {
                  root_url = "https://${cfgMonitor.guiVirtualHost}/";
                  http_addr = "0.0.0.0";
                  enable_gzip = true;
                };
                security = {
                  admin_email = lib.mkIf (cfgMonitor.adminEmail != null) cfgMonitor.adminEmail;
                  admin_password = "$__file{${grafanaAdminPasswordContainerPath}}";
                  strict_transport_security = true;
                  cookie_secure = true;
                };
                users = {
                  default_theme = "system";
                  viewers_can_edit = true;
                };
              };
            };

            services.tailscale.enable = true;

            networking.firewall = {
              enable = true;
              interfaces = with config.services.tailscale; {
                ${interfaceName}.allowedTCPPorts = [ grafanaPort ];
              };
            };
            networking.nftables.enable = true;
          };
      };
    })
  ];
}
