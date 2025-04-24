{ self, ... }:
let
  inherit (self.inputs) clan-core destiny-config destiny-core;
in
{
  perSystem =
    {
      lib,
      pkgs,
      inputs',
      system,
      ...
    }:
    {
      packages.fly-io-pop =
        let
          inherit (inputs'.nix2container.packages) nix2container;
          sops-install-secrets = clan-core.inputs.sops-nix.packages.${system}.sops-install-secrets;
          util-linux = pkgs.util-linux.override (_prev: {
            systemdSupport = false;
            pamSupport = false;
            nlsSupport = false;
          });
          procps = pkgs.procps.override (_prev: {
            withSystemd = false;
          });
          tailscale = (pkgs.tailscale.overrideAttrs (_prev: {
            doCheck = false;
          })).override (_prev: {
            inherit procps;
          });
          vault = inputs'.nixpkgs-unfree.legacyPackages.vault.overrideAttrs (_prev: {
            doCheck = false;
          });
          nginx = pkgs.nginxMainline;
          process-compose = pkgs.process-compose.overrideAttrs (prev: {
            src = pkgs.fetchFromGitHub {
              owner = "lopter";
              repo = prev.pname;
              rev = "05f4a48656640825a7631aa76e0734f10e304e57";
              hash = "sha256-m9PG5xpgmREOBrVMASj/WkXQVlQaknHi7YKfxrgQcIA=";
              # populate values that require us to use git. By doing this in postFetch we
              # can delete .git afterwards and maintain better reproducibility of the src.
              leaveDotGit = true;
              postFetch = ''
                cd "$out"
                git rev-parse --short HEAD > $out/COMMIT
                # in format of 0000-00-00T00:00:00Z
                date -u -d "@$(git log -1 --pretty=%ct)" "+%Y-%m-%dT%H:%M:%SZ" > $out/SOURCE_DATE_EPOCH
                find "$out" -name .git -print0 | xargs -0 rm -rf
              '';
            };
          });
          basePkgs =
            [
              procps
              tailscale
              nginx
              util-linux
              vault
            ]
            ++ (with pkgs; [
              acl
              alacritty.terminfo
              attr
              bashInteractive
              (bind.override (_prev: {
                enableGSSAPI = false;
              })).dnsutils
              cacert
              coreutils
              curl
              fd
              file
              (htop.override (_prev: {
                sensorsSupport = false;
                systemdSupport = false;
              }))
              iftop
              inetutils
              iproute2
              iptables
              jq
              libcap_ng
              less
              lsof
              mosh
              mtr
              netcat-openbsd
              openssh
              openssl
              psmisc
              ripgrep
              rsync
              strace
              sysstat
              tcpdump
              (tmux.override (_prev: {
                withSystemd = false;
                withSixel = false;
              }))
              tree
              unbound
              vis

              sops-install-secrets
            ]);
          shellLayer = {
            copyToRoot = [
              (pkgs.buildEnv {
                name = "root";
                paths = basePkgs;
                pathsToLink = [
                  "/bin"
                  "/etc"
                ];
              })
            ];
          };
          ports = {
            process-compose = "1100";
            nginx = "1101";
            nginx-https = "1102";
            ssh = "1103";
            tailscaled = "41641";
            unbound = "1104";
          };
          processComposeConfig = pkgs.writeTextFile {
            name = "process-compose.yaml";
            checkPhase = ''
              ${process-compose}/bin/process-compose --config "$out" config check
            '';
            text =
              let
                log_rotate_cfg = rec {
                  max_size_mb = 10;
                  max_age_days = 180;
                  max_backups = max_size_mb * 20; # 200MB
                  compress = true;
                };
                mkProcess =
                  name:
                  { ... }@processCfg:
                  processCfg
                  // {
                    log_location = "/var/log/process-compose/${name}.log";
                    log_configuration.rotation = log_rotate_cfg;
                    availability.backoff_seconds = 10;
                  };
              in
              builtins.toJSON {
                is_strict = true;
                log_location = "/var/log/process-compose/process-compose.log";
                log_level = "info";
                log_configuration.rotation = log_rotate_cfg;
                processes = builtins.mapAttrs mkProcess (
                  {
                    postInit = {
                      command = "postInit";
                      # Shut-down the machine if postInit fails:
                      availability.restart = "exit_on_failure";
                    };
                    nginx = {
                      # We cannot have the loop to check for the certificates
                      # in a different process because if it was to fail then
                      # process-compose would just skip running nginx, instead
                      # of waiting for that process to be healthy and then
                      # start nginx.
                      command = pkgs.writeShellScript "wait-for-certificates-and-start-nginx" ''
                        domains=(${lib.concatStringsSep " " (map lib.escapeShellArg certbotDomains)})
                        status=0
                        for each in "''${domains[@]}" ; do
                          if [ ! -f "/var/lib/nginx/certs/$each/chain.pem" ] || [ ! -f "/var/lib/nginx/certs/$each/key.pem" ]; then
                            printf >&2 "Missing certificate for: %s.\n" "$each"
                            status=1
                          fi
                        done

                        if [ $status -ne 0 ] ; then
                          printf >&2 "Cannot start Nginx due to missing certificates.\n"
                          exit $status
                        fi

                        exec runas nginx ${nginx}/bin/nginx -c ${nginxConfig}
                      '';
                      namespace = "nginx";
                      depends_on =
                        {
                          postInit.condition = "process_completed_successfully";
                          tailscaled.condition = "process_healthy";
                          unbound.condition = "process_healthy";
                        }
                        // lib.optionalAttrs (builtins.length certbotDomains > 0) {
                          nginx-vault-agent.condition = "process_healthy";
                        };
                      availability.restart = "always";
                    };
                    sshd = {
                      command = "${pkgs.openssh}/bin/sshd -D -e -f ${sshdConfig}";
                      availability.restart = "always";
                      depends_on.tailscaled.condition = "process_healthy";
                    };
                    unbound = {
                      command = "runas unbound ${pkgs.unbound}/bin/unbound -d -p -c ${unboundConfig}";
                      namespace = "nginx";
                      depends_on.postInit.condition = "process_completed_successfully";
                      availability.restart = "always";
                      readiness_probe.exec.command = ''dig -p ${ports.unbound} nixos.org @127.0.0.1'';
                    };
                    tailscaled = {
                      command = "${tailscale}/bin/tailscaled --state=/var/lib/tailscale/tailscaled.state --port=${ports.tailscaled} --socket=/var/run/tailscale/tailscaled.sock";
                      namespace = "tailscale";
                      availability.restart = "always";
                      depends_on = {
                        postInit.condition = "process_completed_successfully";
                      };
                      readiness_probe.exec.command = ''[ "$(ip -oneline address show tailscale0 2>&- | rg --count inet)" -gt 0 ]'';
                    };
                    tailscaled-autoconnect = {
                      command = "${tailscale}/bin/tailscale up --auth-key=file:/run/secrets/tailscaleAuthKey --hostname=fly-io-pop";
                      namespace = "tailscale";
                      depends_on = {
                        postInit.condition = "process_completed_successfully";
                        tailscaled.condition = "process_started";
                      };
                    };
                  }
                  // lib.optionalAttrs (builtins.length certbotDomains > 0) {
                    nginx-vault-agent = {
                      command = "runas nginx ${vault}/bin/vault agent -config ${nginxVaultAgentConfig}";
                      namespace = "nginx";
                      depends_on = {
                        tailscaled.condition = "process_healthy";
                        postInit.condition = "process_completed_successfully";
                        tailscaled-autoconnect.condition = "process_completed_successfully";
                      };
                      availability.restart = "always";
                      # This is obviously not a good check, since it will return true
                      # even if vault-agent is not properly initialized yet.
                      readiness_probe.exec.command = ''[ "$(pgrep -c vault)" -gt 0 ]'';
                    };
                  }
                );
              };
          };
          sshdConfig = pkgs.writeTextFile {
            name = "sshd_config";
            text = ''
              AuthorizedPrincipalsFile none
              Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr,aes192-ctr,aes128-ctr
              GatewayPorts no
              KbdInteractiveAuthentication no
              KexAlgorithms sntrup761x25519-sha512@openssh.com,curve25519-sha256,curve25519-sha256@libssh.org,diffie-hellman-group-exchange-sha256
              LogLevel INFO
              Macs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com,umac-128-etm@openssh.com
              PasswordAuthentication no
              PermitRootLogin yes
              PrintMotd no
              StrictModes yes
              UseDns no
              UsePAM no
              X11Forwarding no
              Banner none

              AddressFamily any
              Port ${ports.ssh}

              Subsystem sftp ${pkgs.openssh}/libexec/sftp-server

              AuthorizedKeysFile %h/.ssh/authorized_keys /etc/ssh/authorized_keys.d/%u

              HostKey /var/ssh/ssh_host_ed25519_key
            '';
          };
          rootAuthorizedSshKey = pkgs.writeTextFile rec {
            name = "root";
            destination = "/etc/ssh/authorized_keys.d/${name}";
            text = destiny-config.lib.knownSshKeys.louisGPGAuthKey;
          };
          certbotDomains =
          let
            getDomains = instanceCfg: instanceCfg.domains;
            inherit (destiny-config.lib) certbotInstances;
          in
            builtins.concatMap getDomains (builtins.attrValues certbotInstances);
          nginxVaultAgentConfig = (pkgs.formats.json { }).generate "nginx-vault-agent.json" {
            auto_auth = [
              {
                method = [
                  {
                    type = "approle";
                    config = [
                      {
                        role_id_file_path = "/run/secrets/nginxVaultAgentRoleIdPath";
                        secret_id_file_path = "/run/secrets/nginxVaultAgentSecretIdPath";
                      }
                    ];
                  }
                ];
                sink = {
                  file = {
                    config = [
                      {
                        path = "/run/nginx-vault-agent/token";
                      }
                    ];
                  };
                };
              }
            ];
            cache = [
              {
                use_auto_auth_token = true;
              }
            ];
            listener = {
              unix = {
                address = "/run/nginx-vault-agent/socket";
                tls_disable = true;
              };
            };
            # TODO: split the vault-agent config to a different file so that we
            # don't conflict with the ports variable for process-compose:
            vault = [
              {
                address = "https://${destiny-config.lib.vault.fqdn}:${toString destiny-config.lib.ports.vault}";
                ca_cert = "/run/secrets/vaultTLSCACert";
              }
            ];
            template =
              let
                mkTemplate = domain: field: {
                  contents = ''
                    {{ with secret "kv/certbot/domains/${domain}" }}
                    {{ .Data.data.${field} }}
                    {{ end }}
                  '';
                  perms = "0400";
                  error_on_missing_key = true;
                  backup = false;
                  destination = "/var/lib/nginx/certs/${domain}/${field}.pem";
                  exec.command = [
                    (pkgs.writeShellScript "vault-agent-reload-nginx" ''
                      if [ -f ${nginxPidFile} ]; then
                        exec ${lib.getExe' procps "pkill"} -HUP --pidfile ${nginxPidFile}
                      fi
                      exit 0
                    '')
                  ];
                };
                mkDomain = domain: [
                  (mkTemplate domain "key")
                  (mkTemplate domain "chain")
                ];
              in
              builtins.concatMap mkDomain certbotDomains;
          };
          nginxPidFile = "/run/nginx/nginx.pid";
          unboundConfig = pkgs.writeTextFile {
            name = "unbound.conf";
            text = ''
              server:

                access-control: 127.0.0.0/8 allow
                access-control: ::1/128 allow
                auto-trust-anchor-file: /var/lib/unbound/root.key
                chroot: ""
                directory: /var/lib/unbound
                use-syslog: no
                do-daemonize: no
                interface: 127.0.0.1
                interface: ::1
                ip-freebind: yes
                pidfile: ""
                port: ${ports.unbound}
                tls-cert-bundle: /etc/ssl/certs/ca-bundle.crt
                username: ""
              remote-control:
                control-cert-file: /var/lib/unbound/unbound_control.pem
                control-enable: no
                control-interface: 127.0.0.1
                control-interface: ::1
                control-key-file: /var/lib/unbound/unbound_control.key
                server-cert-file: /var/lib/unbound/unbound_server.pem
                server-key-file: /var/lib/unbound/unbound_server.key
            '';
          };
          nginxConfig = pkgs.writers.writeNginxConfig "nginx.conf" (''
            pid ${nginxPidFile};
            error_log stderr;
            daemon off;
            events {
            }
            http {
              http2 on;
              # Load mime types and configure maximum size of the types hash tables.
              include ${pkgs.mailcap}/etc/nginx/mime.types;
              types_hash_max_size 2688;
              include ${nginx}/conf/fastcgi.conf;
              include ${nginx}/conf/uwsgi_params;
              default_type application/octet-stream;
              log_subrequest on;
              log_format proxy_proto_combined '$proxy_protocol_addr - $remote_user [$time_local] '
                                              '"$request" $status $body_bytes_sent '
                                              '"$http_referer" "$http_user_agent"';
              access_log /var/log/nginx/access.log proxy_proto_combined;
              sendfile on;
              tcp_nopush on;
              tcp_nodelay on;
              keepalive_timeout 65;
              ssl_protocols TLSv1.2 TLSv1.3;
              ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384:DHE-RSA-CHACHA20-POLY1305;
              ssl_dhparam /var/lib/dhparams/nginx.pem;
              # Keep in sync with https://ssl-config.mozilla.org/#server=nginx&config=intermediate
              ssl_session_timeout 1d;
              ssl_session_cache shared:SSL:10m;
              # Breaks forward secrecy: https://github.com/mozilla/server-side-tls/issues/135
              ssl_session_tickets off;
              # We don't enable insecure ciphers by default, so this allows
              # clients to pick the most performant, per https://github.com/mozilla/server-side-tls/issues/260
              ssl_prefer_server_ciphers off;
              # OCSP stapling
              ssl_stapling on;
              ssl_stapling_verify on;
              gzip on;
              gzip_static on;
              gzip_vary on;
              gzip_comp_level 5;
              gzip_min_length 256;
              gzip_proxied expired no-cache no-store private auth;
              gzip_types application/atom+xml application/geo+json application/javascript application/json application/ld+json application/manifest+json application/rdf+xml application/vnd.ms-fontobject application/wasm application/x-rss+xml application/x-web-app-manifest+json application/xhtml+xml application/xliff+xml application/xml font/collection font/otf font/ttf image/bmp image/svg+xml image/vnd.microsoft.icon text/cache-manifest text/calendar text/css text/csv text/javascript text/markdown text/plain text/vcard text/vnd.rim.location.xloc text/vtt text/x-component text/xml;
              proxy_cache_path /var/cache/nginx levels=1:2 keys_zone=pop-cache:100m max_size=1g inactive=182d use_temp_path=off;
              proxy_cache_key $scheme$host$request_uri;
              proxy_cache pop-cache;
              proxy_redirect          off;
              proxy_connect_timeout   3s;
              proxy_send_timeout      3s;
              proxy_read_timeout      3s;
              proxy_http_version      1.1;
              # don't let clients close the keep-alive connection to upstream. See the nginx blog for details:
              # https://www.nginx.com/blog/avoiding-top-10-nginx-configuration-mistakes/#no-keepalives
              proxy_set_header        "Connection" "";
              proxy_set_header        Host $host;
              proxy_set_header        X-Real-IP $proxy_protocol_addr;
              proxy_set_header        X-Forwarded-For $proxy_protocol_addr;
              proxy_set_header        X-Forwarded-Proto $scheme;
              proxy_set_header        X-Forwarded-Host $host;
              proxy_set_header        X-Forwarded-Server $host;
              set_real_ip_from        172.16.0.0/16; # https://community.fly.io/t/nginx-proxy-protocol-and-set-real-ip-from/24648/3
              # $connection_upgrade is used for websocket proxying
              map $http_upgrade $connection_upgrade {
                      default upgrade;
                      '''      close;
              }
              client_max_body_size 10m;
              client_body_temp_path /run/nginx/client_body;
              proxy_temp_path /run/nginx/proxy;
              fastcgi_temp_path /run/nginx/fastcgi;
              uwsgi_temp_path /run/nginx/uwsgi;
              scgi_temp_path /run/nginx/scgi;
              server_tokens off;
              resolver 127.0.0.1:${ports.unbound};
          ''
          + (destiny-config.lib.popNginxConfig { inherit destiny-core ports; })
          # + (destiny-config.lib.popNginxConfig { inherit destiny-core destiny-config ports; })
          + "}");
          # Only one volume per machine:
          derivationArgs = { };
          mkVarDir = pkgs.runCommand "mkVarDir" derivationArgs ''
            mkdir -p $out/var
          '';
          mountPointLayer = {
            copyToRoot = [ mkVarDir ];
            perms = [
              {
                path = mkVarDir;
                regex = ".*";
                mode = "0755";
              }
            ];
          };
          postInit = pkgs.writeShellApplication {
            name = "postInit";
            runtimeInputs = with pkgs; [ coreutils ];
            text =
              let
                inherit (destiny-config.lib.usergroups.users) nginx unbound;
                nginxUid = builtins.toString nginx.uid;
                nginxGid = builtins.toString nginx.gid;
                unboundUid = builtins.toString unbound.uid;
                unboundGid = builtins.toString unbound.gid;
              in
              ''
                install -d -o ${nginxUid} -g ${nginxGid} /run/nginx
                install -d -o ${nginxUid} -g ${nginxGid} /run/nginx/{client_body,proxy,fastcgi,uwsgi,scgi}
                install -d -o ${nginxUid} -g ${nginxGid} -m 700 /run/nginx-vault-agent
                install -d /run/tailscale

                install -d /var/empty

                install -d /var/cache
                install -d -o ${nginxUid} -g ${nginxGid} -m 700 /var/cache/nginx

                install -d /var/lib
                install -d -o ${nginxUid} -g ${nginxGid} -m 700 /var/lib/nginx
                install -d -o ${nginxUid} -g ${nginxGid} -m 700 /var/lib/nginx/certs
                install -d -o ${unboundUid} -g ${unboundGid} -m 700 /var/lib/unbound
                install -d -m 700 /var/lib/tailscale
                install -d /var/lib/dhparams

                # This takes a very long time to generate so maybe we could ship it as a secret
                [ -f /var/lib/dhparams/nginx.pem ] || {
                  echo "Generating /var/lib/dhparams/nginx.pem, this may take hours on a slow machine or VPS"
                  openssl dhparam -out /var/lib/dhparams/nginx.pem 2048;
                }

                ${pkgs.unbound}/bin/unbound-anchor -a /var/lib/unbound/root.key || {
                  echo "Updated unbound's root anchor";
                }

                install -d /var/run/tailscale

                install -d -m 700 /var/log/process-compose
                install -d -o ${nginxUid} -g ${nginxGid} /var/log/nginx

                [ -f /var/ssh/ssh_host_ed25519_key ] || {
                  echo "Generating new SSH Host identity"
                  install -d /var/ssh
                  ssh-keygen -f /var/ssh/ssh_host_ed25519_key -N "" -t ed25519
                  printf "Generated SSH Host identity, public key: %s\n" "$(cat /var/ssh/ssh_host_ed25519_key.pub)"
                  # shellcheck disable=SC2016
                  printf 'Please add the new key to "secrets.yaml" using "sops rotate -i --add-age $(echo "%s" | ssh-to-age) secrets.yaml"\n' "$(cat /var/ssh/ssh_host_ed25519_key.pub)"
                  printf 'And edit "pop-sops" in "flake.nix" with the new recipient\n'
                  echo >&2 'postInit: failed on new SSH Host identity'
                  exit 1;
                }

                ${sops-install-secrets}/bin/sops-install-secrets ${secretsManifest}
              '';
          };
          withUserBase =
            attrs:
            attrs
            // {
              root = {
                uid = 0;
                gid = 0;
                home = "/root";
                shell = "${pkgs.bashInteractive}/bin/bash";
                lockAccount = false;
              };
              sshd = {
                uid = 1;
                gid = 1;
                home = "/var/empty";
                shell = "${util-linux}/bin/nologin";
              };
              nobody = {
                uid = 65534;
                gid = 65534;
                home = "/var/empty";
                shell = "${util-linux}/bin/nologin";
              };
            };
          withGroupBase =
            attrs:
            attrs
            // {
              root.gid = 0;
              sshd.gid = 1;
              nogroup.gid = 65534;
            };
          dockerNssHelpers = destiny-core.lib.dockerNssHelpers pkgs;
          usergroups =
            with destiny-config.lib.usergroups;
            dockerNssHelpers (withGroupBase groups) (withUserBase users);
          result = lib.nixos.evalModules {
            modules = [
              ./sops-nix.nix
              "${self.inputs.nixpkgs}/nixos/modules/misc/assertions.nix"
              {
                # If you don't use any of `config`, `options`, or `imports`,
                # at the root of your module, then `evalModules` assumes
                # everything was under `config`.
                sops.age.sshKeyPaths = [ "/var/ssh/ssh_host_ed25519_key" ];
                sops.defaultSopsFile = ./secrets.yaml;
                sops.secrets.tailscaleAuthKey = { };
                sops.secrets.nginxVaultAgentRoleIdPath = {
                  owner = "nginx";
                  group = "nginx";
                };
                sops.secrets.nginxVaultAgentSecretIdPath = {
                  owner = "nginx";
                  group = "nginx";
                };
                sops.secrets.vaultTLSCACert.mode = "0444";
              }
            ];
            specialArgs = {
              inherit
                lib
                pkgs
                self
                system
                ;
            };
          };
          secretsManifest = result.config.clan-destiny.fly-io-pop.secretsManifest;
          configLayer = {
            deps = [
              processComposeConfig
              secretsManifest
              sshdConfig
            ];
            copyToRoot = [
              (pkgs.buildEnv {
                name = "usergroups";
                paths = [
                  usergroups
                  postInit
                  # Since we did not setup PAM, we need some more rudimentary way to drop privs:
                  (pkgs.stdenv.mkDerivation {
                    pname = "runas";
                    version = "0.1";
                    src = pkgs.writeTextDir "src/runas.c" ''
                      #include <sys/types.h>
                      #include <errno.h>
                      #include <grp.h>
                      #include <stdlib.h>
                      #include <pwd.h>
                      #include <stdio.h>
                      #include <string.h>
                      #include <unistd.h>

                      extern char **environ;

                      void
                      xsetenv(const char *name, const char *value)
                      {
                        const int overwrite = 1;
                        if (setenv(name, value, overwrite) != 0) {
                          fprintf(stderr, "setenv %s failed: %s\n", name, strerror(errno));
                          exit(1);
                        }
                      }

                      int
                      main(int argc, char *argv[])
                      {
                        if (argc < 3) {
                          fprintf(stderr, "Usage: %s user cmd ...\n", argv[0]);
                          exit(1);
                        }

                        struct passwd *entry = getpwnam(argv[1]);
                        if (entry == NULL) {
                          perror("getpwnam failed");
                          exit(1);
                        }

                        if (initgroups(entry->pw_name, entry->pw_gid) != 0) {
                          perror("initgroups failed");
                          exit(1);
                        }

                        if (setgid(entry->pw_gid) != 0) {
                          perror("setgid failed");
                          exit(1);
                        }

                        if (setuid(entry->pw_uid) != 0) {
                          perror("setuid failed");
                          exit(1);
                        }

                        if (clearenv() != 0) {
                          perror("clearenv failed");
                          exit(1);
                        }

                        xsetenv("HOME", entry->pw_dir);
                        xsetenv("USER", entry->pw_name);
                        xsetenv("PATH", "/bin");

                        execvpe(argv[2], &argv[2], environ);
                        perror("execvpe failed");
                        exit(1);
                      }
                    '';
                    buildPhase = ''
                      gcc -Wall -Wextra -Werror -O2 -D _GNU_SOURCE=1 -o runas src/runas.c
                    '';
                    installPhase = ''
                      mkdir -p $out/bin
                      cp runas $out/bin
                    '';
                  })

                  (pkgs.writeShellApplication {
                    name = "show-config";
                    runtimeInputs = with pkgs; [
                      jq
                      less
                    ];
                    text = ''
                      if [ -t 1 ]; then
                        jq -C <"${processComposeConfig}" | less -FRX
                      else
                        jq <"${processComposeConfig}"
                      fi
                    '';
                  })

                  (pkgs.writeShellScriptBin "pc" ''
                    exec ${process-compose}/bin/process-compose attach -u /run/process-compose.sock
                  '')

                  (pkgs.writeShellScriptBin "test-nginx-config" ''
                    exec ${nginx}/bin/nginx -t -c ${nginxConfig}
                  '')

                  rootAuthorizedSshKey
                ];
                pathsToLink = [
                  "/bin"
                  "/etc"
                ];
              })
            ];
          };
          mkLayer = prevLayers: layerParams:
          let
            layer = nix2container.buildLayer (layerParams // { layers = prevLayers; });
          in
            prevLayers ++ [ layer ];
          assembleLayers = layers: builtins.foldl' mkLayer [ ] layers;
        in
        nix2container.buildImage {
          name = "registry.fly.io/clan-destiny-pop";
          config = {
            env = [
              "PATH=/bin"
            ];
            cmd = [
              "${process-compose}/bin/process-compose"
              "up"
              "--config=${processComposeConfig}"
              "--tui=false"
              "--port=${ports.process-compose}"
              "--ordered-shutdown"
              "--unix-socket=/run/process-compose.sock"
            ];
          };
          layers = assembleLayers [
            shellLayer
            mountPointLayer
            configLayer
          ];
        };
    };
}
