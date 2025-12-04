{
  config,
  lib,
  pkgs,
  self,
  ...
}:
let
  inherit (config.lib.clan-destiny) ports usergroups;
  inherit (self.inputs) home-manager;

  cfg = config.clan-destiny.starrs-gate;
  vars = config.clan.core.vars.generators.clan-destiny-starrs-gate;

  xrdpHomeDir = "/var/lib/xrdp";
  userPasswordHashContainerPath = "/run/secrets/userPasswordHash";
  containerUserCfg = {
    groups.xrdp.gid = lib.mkForce usergroups.users.xrdp.gid;
    users.xrdp = {
      uid = lib.mkForce usergroups.users.xrdp.uid;
      group = "xrdp";
      home = xrdpHomeDir;
      isSystemUser = true;
      createHome = true;
    };
    groups.${cfg.user}.gid = lib.mkForce usergroups.users.${cfg.user}.gid;
    users.${cfg.user} = {
      uid = lib.mkForce usergroups.users.${cfg.user}.uid;
      group = cfg.user;
      home = lib.mkForce "/home/${cfg.user}";
      isNormalUser = true;
      createHome = false;
      hashedPasswordFile = userPasswordHashContainerPath;
    };
  };
  hostUserCfg = lib.recursiveUpdate containerUserCfg {
    users.${cfg.user} = {
      home = lib.mkForce (cfg.dataDir + "/home");
      isSystemUser = true;
      isNormalUser = false;
      createHome = true;
      hashedPasswordFile = null;
    };
  };
in
{
  options.clan-destiny.starrs-gate = with lib; {
    enable = mkEnableOption "Firefox & Tailscale exit-node container";
    macvlans = mkOption {
      description = ''
        "Bridge" the container to the local network via those interfaces.
      '';
      type = types.nonEmptyListOf types.str;
    };
    user = mkOption {
      description = ''
        The name of the user in `config.lib.clan-destiny.usergroups` to create
        as a normal user in the container and as a system user on the host.
      '';
      type = types.nonEmptyStr;
    };
    hostName = mkOption {
      type = types.nonEmptyStr;
      description = "Hostname to use in the container";
    };
    domain = mkOption {
      type = types.nonEmptyStr;
      description = "Domain to use in the container";
    };
    tlsServerName = mkOption {
      type = types.nonEmptyStr;
      description = "FQDN to use for the TLS cert for xrdp";
    };
    dataDir = mkOption {
      description = ''
        A `tailscale` and `home` directory will be created inside this
        directory, and bind-mounted to `/var/lib/tailscale` and
        `/home/${cfg.user}` respectively, inside the container.
      '';
      type = types.path;
    };
  };

  config = lib.mkIf cfg.enable {
    clan.core.vars.generators.clan-destiny-starrs-gate = {
      files.userPassword.deploy = false;
      files.userPasswordHash = { };
      files.vaultRoleId.owner = "xrdp";
      files.vaultRoleId.group = "xrdp";
      files.vaultSecretId.owner = "xrdp";
      files.vaultSecretId.group = "xrdp";
      prompts.vaultRoleId = {
        persist = true;
        description = "The Vault Role ID for certbot-vault";
        type = "hidden";
      };
      prompts.vaultSecretId = {
        persist = true;
        description = "The Vault Secret ID for certbot-vault";
        type = "hidden";
      };
      # This one is useful to consult the generated value:
      prompts.userPassword = {
        persist = true;
        description = "User password for ${cfg.user} (leave empty to generate one)";
        type = "hidden";
      };
      runtimeInputs = with pkgs; [
        coreutils
        xkcdpass
        mkpasswd
      ];
      # Credits to clan-core:
      script = ''
        trim() {
          awk '{ gsub(/^[[:space:]]+|[[:space:]]+$/, ""); print }'
        }

        if [ -z "$(trim < "$prompts/userPassword" | tee "$out/userPassword")" ]; then
          xkcdpass --numwords 4 --delimiter - --count 1 | trim > $out/userPassword
        fi
        mkpasswd -s -m sha-512 < "$out/userPassword" | trim > "$out/userPasswordHash"
      '';
    };

    clan-destiny.certbot-vault-agents.xrdp = {
      certsDirectory = xrdpHomeDir;
      domains = [ cfg.tlsServerName ];
      roleIdFilePath = vars.files.vaultRoleId.path;
      secretIdFilePath = vars.files.vaultSecretId.path;
      user = "xrdp";
      group = "xrdp";
    };

    containers.starrs-gate = {
      inherit (cfg) macvlans;
      ephemeral = true;
      autoStart = true;
      enableTun = true; # to be able to use tailscale in the container
      bindMounts = {
        "/home/${cfg.user}" = {
          hostPath = cfg.dataDir + "/home";
          isReadOnly = false;
        };
        "/var/lib/tailscale" = {
          hostPath = cfg.dataDir + "/tailscale";
          isReadOnly = false;
        };
        "${xrdpHomeDir}" = {
          hostPath = xrdpHomeDir;
          isReadOnly = false;
        };
        "${userPasswordHashContainerPath}" = {
          hostPath = vars.files.userPasswordHash.path;
          isReadOnly = true;
        };
      };
      config =
        { pkgs, ... }:
        {
          imports = [
            home-manager.nixosModules.home-manager

            self.nixosModules.containers
            self.nixosModules.fonts
            self.nixosModules.nixpkgs
          ];

          clan-destiny.containers = { inherit (cfg) macvlans; };

          environment.systemPackages = with pkgs; [
            openbox
            xterm
          ];

          # Move files overwritten by lxqt out of our way,
          # since it insists on rewriting session.conf:
          home-manager.backupFileExtension = "local";

          home-manager.users.${cfg.user} =
            { ... }:
            {
              home.homeDirectory = "/home/${cfg.user}";
              home.stateVersion = "25.05";
              home.file.".config/lxqt/session.conf".text = ''
                window_manager=${pkgs.openbox}/bin/openbox
              '';

              programs.firefox = {
                enable = true;
              };
            };

          networking = {
            inherit (cfg) hostName domain;
            firewall.enable = false;
          };

          services.xserver.desktopManager.lxqt.enable = true;

          services.tailscale = {
            enable = true;
            port = ports.tailscale;
            extraUpFlags = [
              "--advertise-exit-node=true"
            ];
          };

          services.xrdp = {
            enable = true;
            sslKey = "${xrdpHomeDir}/${cfg.tlsServerName}/key.pem";
            sslCert = "${xrdpHomeDir}/${cfg.tlsServerName}/chain.pem";
            defaultWindowManager = "${pkgs.lxqt.lxqt-session}/bin/startlxqt";
            extraConfDirCommands = ''
              substituteInPlace $out/xrdp.ini \
                --replace "security_layer=negotiate" "security_layer=tls"
            '';
          };

          time.timeZone = "UTC";

          users = containerUserCfg;
        };
    };


    systemd.tmpfiles.rules =
    let
      tailscaleDir = cfg.dataDir + "/tailscale";
    in [
      "d ${tailscaleDir} 0700 root root - -"
    ];

    users = hostUserCfg;
  };
}
