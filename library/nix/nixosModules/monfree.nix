{
  config,
  lib,
  pkgs,
  self,
  utils,
  ...
}:
let
  inherit (self.inputs.destiny-core.packages.${system}) monfree;
  inherit (pkgs.stdenv.hostPlatform) system;
  inherit (config.lib.clan-destiny) mkContainer usergroups;
  inherit (config.clan-destiny.typed-tags) interfacesByRole;
in
{
  options.clan-destiny.monfree = {
    exporter = {
      enable = lib.mkEnableOption "Enable mtr based monitoring service (exporter component)";
      endpoints = lib.mkOption {
        description = "The list of endpoints (IPv4/6) to monitor using `mtr`";
        type = with lib.types; nonEmptyListOf nonEmptyStr;
      };
      sources = lib.mkOption {
        description = "Your public IPv4/6 used to monitor the endpoints using `mtr`";
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
      interval = lib.mkOption {
        description = "Prometheus scrape interval";
        type = lib.types.int;
        default = 60;
      };
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
        ]
        ++ map (endpoint: "--endpoint=${endpoint}") cfgExporter.endpoints
        ++ map (source: "--source=${source}") cfgExporter.sources);
        Restart = "on-failure";
        RestartSec = 5;
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

    grafanaAdminPasswordHostPath = varsMonitor.files.grafana-admin-password.path;
    # Credentials loaded via LoadCredential on the container service are propagated
    # into the container and can be imported by services using ImportCredential.
    # When imported by Grafana, the credential is available at this path:
    grafanaAdminPasswordContainerPath = "/run/credentials/grafana.service/grafana-admin-password";
    grafanaPort = config.services.grafana.settings.server.http_port;
    victoriaMetricsPort = 8428;

    scrapeConfigs = [
      {
        job_name = "monfree";
        static_configs = [{ targets = cfgMonitor.exporters; }];
      }
    ];

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

      # Using a container allows us to run a separate Prometheus instance for
      # which I don't care about backing up its data.
      containers.monfree = mkContainer {
        # We still want to keep the data across reboot and deploys and have an
        # opportunity to export our grafana dashboards, maybe declare them here.
        ephemeral = false;
        privateNetwork = true;
        privateUsers = "pick";
        additionalCapabilities  = [ "CAP_NET_RAW" ];
        # Pass the Grafana admin password to the container via systemd credentials.
        # This works with Grafana's $__file{} mechanism via ImportCredential.
        extraFlags = [
          "--load-credential=grafana-admin-password:${grafanaAdminPasswordHostPath}"
        ];
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
              inherit scrapeConfigs;
            };

            services.victoriametrics = {
              enable = true;
              listenAddress = "127.0.0.1:${toString victoriaMetricsPort}";
              prometheusConfig = {
                global.scrape_interval = "${toString cfgMonitor.interval}s";
                scrape_configs = scrapeConfigs;
              };
            };

            # Import the credential propagated by systemd-nspawn from the host.
            systemd.services.grafana.serviceConfig.ImportCredential = [
              "grafana-admin-password"
            ];

            services.grafana = {
              enable = true;
              declarativePlugins = with pkgs.grafanaPlugins; [
                victoriametrics-metrics-datasource
              ];
              provision = {
                enable = true;
                datasources.settings = {
                  prune = false;
                  datasources = [
                    {
                      name = "Prometheus";
                      type = "prometheus";
                      url = "http://127.0.0.1:${toString config.services.prometheus.port}";
                      jsonData = {
                        timeInterval = "${toString cfgMonitor.interval}s";
                        prometheusType = "Prometheus";
                        prometheusVersion = pkgs.prometheus.version;
                      };
                    }
                    {
                      name = "VictoriaMetrics";
                      type = "victoriametrics-metrics-datasource";
                      url = "http://127.0.0.1:${toString victoriaMetricsPort}";
                      jsonData = {
                        timeInterval = "${toString cfgMonitor.interval}s";
                      };
                    }
                  ];
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
