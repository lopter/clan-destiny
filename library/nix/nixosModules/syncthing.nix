{ config, lib, pkgs, self, ... }:
let
  inherit (self.inputs.destiny-config.lib) popAddresses usergroups;
  inherit (config.networking) hostName domain;
  inherit (pkgs.stdenv.hostPlatform) system;

  cfg = config.clan-destiny.syncthing;

  zone = self.lib.zoneFromHostname hostName;
  mkContainerHostnameForUser = name: lib.concatStringsSep "-" [
    "syncthing" name zone cfg.containerHostnameSuffix
  ];

  # The syncthing GUI for each user is exposed
  # from the host at this virtual host using Nginx.
  guiVirtualHost = "syncthing-${zone}.${domain}";

  # Syncthing will communicate to the outside using MACVLAN.
  #
  # OTOH we want to expose the Syncthing GUI to our users, and to avoid running
  # Tailscale in each container, the host will proxy the GUIs, however the host
  # cannot communicate to a container on its MACVLAN interface, so we will use
  # a veth pair for that:
  mkVethPair = acc: userName:
  let
    count = builtins.length acc;
    nextIP = count * 2 + 1;
    vethDetails = {
      name = "st${toString count}";
      hostAddress = "10.172.28.${toString nextIP}";
      localAddress = "10.172.28.${toString (nextIP + 1)}";
    };
  in
    acc ++ [ (lib.nameValuePair userName vethDetails) ];
  vethsByUser = builtins.listToAttrs (builtins.foldl' mkVethPair [ ] cfg.createUserAccounts);
in
{
  options.clan-destiny.syncthing = with lib; {
    createUserAccounts = mkOption {
      type = with types; listOf (enum (builtins.attrNames usergroups.familyUsers));
      description = ''
        Create Syncthing credentials using vars for each listed user. This is
        useful on its own to generate credentials for use in home-manager.
      '';
      default = cfg.createUserSystemInstances;
    };
    createUserSystemInstances = mkOption {
      type = with types; listOf (enum (builtins.attrNames usergroups.familyUsers));
      description = ''
        Create a Syncthing container that will run as a system unit for each
        listed user. This is mostly useful on a server; on a workstation you
        probably want to use user systemd units (e.g. through home-manager), so
        that syncthing is only running when a particular user is logged-in.
      '';
      default = [ ];
    };
    containerHostnameSuffix = mkOption {
      type = with types; nullOr nonEmptyStr;
      description = ''
        This suffix is used to identify the host Syncting is running on.

        It is appended to "syncthing-''${zone}-''${userName}-", and the result
        is used as the hostname for the container of the syncthing instance of
        that user. Syncthing will use this hostname as the device name.

        It is also used to configure HTTP proxying to each GUI for each user.
        The proxy will resolve the IP of each Syncthing instance using DNS, so
        records have to be set.
      '';
      default = null;
    };
  };

  config = lib.mkMerge [
    (lib.mkIf ((builtins.length cfg.createUserAccounts) > 0) {
      clan.core.vars.generators.clan-destiny-syncthing-accounts =
      let
        mkFiles = userName: [
          (lib.nameValuePair "${userName}-cert" { owner = userName; group = userName; })
          (lib.nameValuePair "${userName}-key" { owner = userName; group = userName; })
          (lib.nameValuePair "${userName}-apiKey" { owner = userName; group = userName; })
          (lib.nameValuePair "${userName}-deviceId" { secret = false; })
        ];
        # Credit to clan-core for the script:
        mkScript = userName: ''
          syncthing generate --config $out
          mv $out/key.pem $out/${userName}-key
          mv $out/cert.pem $out/${userName}-cert
          grep -oP '(?<=<device id=")[^"]+' $out/config.xml | uniq | trim > $out/${userName}-deviceId
          grep -oP '<apikey>\K[^<]+' $out/config.xml | uniq | trim > $out/${userName}-apiKey
          rm $out/config.xml
        '';
      in
      {
        files = builtins.listToAttrs (builtins.concatMap mkFiles cfg.createUserAccounts);
        runtimeInputs = with pkgs; [
          coreutils
          gnugrep
          syncthing
        ];
        script = ''
          trim() {
            tr -d "\n"
          }

          ${lib.concatLines (map mkScript cfg.createUserAccounts)}
        '';
      };
    })
    (lib.mkIf ((builtins.length cfg.createUserSystemInstances) > 0) {
      assertions = [
        {
          assertion = config.clan-destiny.usergroups.createNormalUsers;
          message = ''
            family users and groups must be created (see option
            `clan-destiny.usergroups.createNormalUsers`) in order
            to create their syncthing accounts.
          '';
        }
      ];

      clan-destiny.nginx.enable = true;
      clan-destiny.nginx.resolver.enable = true;

      containers =
      let
        inherit (config.lib.clan-destiny) mkContainer;
        syncthingVars = config.clan.core.vars.generators.clan-destiny-syncthing-accounts;
        certContainerPath = "/run/secrets/syncthing-cert.pem";
        keyContainerPath = "/run/secrets/syncthing-key.pem";
        apiKeyContainerPath = "/run/secrets/syncthing-apiKey.pem";
        mkContainerForUser = name: {
          name = mkContainerHostnameForUser name;
          value =
          let
            veth = vethsByUser.${name};
            syncthingUserFolder = "/stash/home/${name}/syncthing";
            syncthingUserVolume = "/stash/volumes/syncthing/${name}";
          in
            mkContainer {
            # Use extraVeths to avoid the veth being added as a default route.
            extraVeths.${veth.name} = {
              inherit (veth) localAddress hostAddress;
            };
            privateNetwork = true;
            bindMounts = {
              ${certContainerPath}.hostPath = syncthingVars.files."${name}-cert".path;
              ${keyContainerPath}.hostPath = syncthingVars.files."${name}-key".path;
              ${apiKeyContainerPath}.hostPath = syncthingVars.files."${name}-apiKey".path;
              ${syncthingUserVolume} = {
                hostPath = syncthingUserVolume;
                isReadOnly = false;
              };
              ${syncthingUserFolder} = {
                hostPath = syncthingUserFolder;
                isReadOnly = false;
              };
            };
            config =
              { pkgs, ... }:
              {
                clan-destiny.usergroups.createNormalUsers = true;

                services.syncthing =
                {
                  enable = true;
                  user = name;
                  group = name;
                  configDir = "${syncthingUserVolume}/config";
                  databaseDir = "${syncthingUserVolume}/db";
                  guiAddress = "0.0.0.0:8384";
                  cert = certContainerPath;
                  key = keyContainerPath;
                  apiKeyFile = apiKeyContainerPath;
                  openDefaultPorts = true;
                  overrideDevices = false; # let users manage their devices
                  overrideFolders = false;
                  settings = {
                    gui.insecureAdminAccess = true;
                    options = {
                      urAccepted = -1;
                      localAnnounceEnabled = true;
                    };
                    "defaults/ignores".lines = [
                      "#include ignore-patterns.txt"
                    ];
                    folders.${syncthingUserFolder} = {
                      id = "syncthing";
                      label = "Syncthing directory";
                      autoNormalize = false;
                      caseSensitiveFS = true;
                    };
                  };
                };

                systemd.services.syncthing.serviceConfig = {
                  ProtectSystem = "strict";
                  ReadWritePaths = [
                    syncthingUserFolder
                    syncthingUserVolume
                  ];
                };
                systemd.services."syncthing-init-ignores-${name}" =
                  self.lib.mkSyncthingInitIgnoreService pkgs name;

                networking.firewall = {
                  enable = true;
                  # The host will proxy traffic to the GUI
                  # so allow access from the host:
                  extraInputRules = ''
                    ip saddr ${veth.hostAddress} tcp dport 8384 accept comment "${hostName} -> syncthing-gui"
                  '';
                };
                networking.nftables.enable = true;
              };
          };
        };
      in
        builtins.listToAttrs (map mkContainerForUser cfg.createUserAccounts);

      # Use PAM to authenticate syncthing users until
      # we get something more approriate like kanidm.
      #
      # Also maybe we could do that through auth_request, to do better privsep,
      # and keep Nginx out of the shadow group, it would also help us implement
      # some global rate limiting, global meaning a single counter for the whole
      # world, as opposed to some IP in particular.
      security.pam.services.nginx-syncthing.text = with pkgs; ''
        account required ${pam}/lib/security/pam_unix.so
        auth sufficient ${pam}/lib/security/pam_unix.so likeauth
        auth required ${pam}/lib/security/pam_deny.so
      '';
      services.nginx.package = self.packages.${system}.nginxWithPamSupport;
      users.users.nginx.extraGroups = [ "shadow" ];
      systemd.services.nginx.serviceConfig = {
          NoNewPrivileges = lib.mkForce false;
          CapabilityBoundingSet = lib.mkForce [
            "CAP_AUDIT_WRITE"
            "CAP_NET_BIND_SERVICE"
            "CAP_SETGID"
            "CAP_SETUID"
          ];
          SystemCallFilter = lib.mkForce [
            "@system-service"
            "@setuid"
          ];
      };

      # TODO: Figure out how to link other Syncthing instances in the zone. Maybe
      # the clan inventory can be used for that. Then split this is out in a
      # standalone module.
      services.nginx.virtualHosts.${guiVirtualHost} =
      let
        mkLocationsForUser = name:
        let
          userLandingPage = pkgs.writeTextDir "index.html" ''
            <!DOCTYPE html>
            <html lang="en">
              <head>
                <meta charset="utf-8"/>
                <meta name="viewport" content="width=device-width, initial-scale=1"/>
                <title>Syncthing [${lib.toUpper zone}]</title>
              </head>
              <body>
                <h1>Serveurs Syncthing pour ${name} à ${lib.toUpper zone}</h1>
                <ul>
                  <li><a href=/${name}/${cfg.containerHostnameSuffix}/>${cfg.containerHostnameSuffix}</li>
                </ul>
              </body>
            </html>
          '';
        in
        [
          (lib.nameValuePair "= /${name}" { return = "301 /${name}/"; })
          {
            name = "/${name}/";
            value = {
              alias = userLandingPage + "/";
              index = "index.html";
            };
          }
          {
            name = "/${name}/${cfg.containerHostnameSuffix}/";
            value = {
              proxyPass = "http://${vethsByUser.${name}.localAddress}:8384";
              extraConfig = ''
                auth_pam              "${mkContainerHostnameForUser name}";
                auth_pam_service_name "nginx-syncthing";

                rewrite /${name}/${cfg.containerHostnameSuffix}/(.*) /$1 break;

                proxy_read_timeout 600s;
                proxy_send_timeout 600s;
              '';
            };
          }
        ];
        usersLocations = builtins.concatMap mkLocationsForUser cfg.createUserAccounts;

        rootLocation = lib.nameValuePair "/" {
          alias = (pkgs.writeTextDir "index.html" ''
            <!DOCTYPE html>
            <html lang="en">
              <head>
                <meta charset="utf-8"/>
                <meta name="viewport" content="width=device-width, initial-scale=1"/>
                <title>Syncthing [${lib.toUpper zone}]</title>
              </head>
              <body>
                <h1>Serveur Syncthing ${lib.toUpper zone}</h1>
                <p>Veuillez ajouter votre nom d'utilisateur à l'URL pour accéder à votre interface Syncthing.</p>
              </body>
            </html>
          '') + "/";
          index = "index.html";
        };
      in
      {
        extraConfig = (lib.concatMapStringsSep "\n" (addr: "allow ${addr.v4};") popAddresses) + ''
          deny all;
        '';
        locations = builtins.listToAttrs (usersLocations ++ [ rootLocation ]);
      };

      systemd.tmpfiles.rules =
      let
        mkDirsForUser = name: [
          "d /stash/volumes/syncthing 0755 root root -"
          "d /stash/volumes/syncthing/${name} 0700 ${name} ${name} -"
          "d /stash/home/${name}/syncthing 0700 ${name} ${name} - -"
        ];
      in
        builtins.concatMap mkDirsForUser cfg.createUserAccounts;
    })
  ];
}
