{ config, lib, ... }:
let
  cfg = nginxCfg.nixos-proxy-cache;
  nginxCfg = config.clan-destiny.nginx;
  nginxUser = config.services.nginx.user;
  nginxGroup = config.services.nginx.group;

  cacheName = "nixos-proxy-cache";
in
{
  options.clan-destiny.nginx.nixos-proxy-cache = {
    enable = lib.mkEnableOption "Setup a read-through cache for cache.nixos.org";
    storageDir = lib.mkOption {
      type = lib.types.path;
      description = ''
        Storage directory for cached NixOS packages.

        The directory is created with `systemd.tmpfiles`.
      '';
    };
    maxSize = lib.mkOption {
      type = lib.types.nonEmptyStr;
      description = "Size of the cache";
      default = "25g";
    };
    inactive = lib.mkOption {
      type = lib.types.nonEmptyStr;
      default = "182d";
      description = ''
        Evict files that have not been accessed
        by this period of time from the cache.
      '';
    };
    serverNames = lib.mkOption {
      type = with lib.types; nonEmptyListOf nonEmptyStr;
      description = "Name of the http virtual host for the cache.";
    };
  };

  config = lib.mkIf cfg.enable {
    clan-destiny.nginx.enable = true;
    clan-destiny.nginx.resolver.enable = true;

    services.nginx = {
      appendHttpConfig = ''
        proxy_cache_path ${cfg.storageDir} levels=1:2 keys_zone=${cacheName}:100m max_size=${cfg.maxSize} inactive=${cfg.inactive} use_temp_path=off;

        # Cache only success status codes; in particular we don't want to cache 404s.
        # See https://serverfault.com/a/690258/128321
        map $status $nixos_proxy_cache_control {
          200     "public";
          302     "public";
          default "no-store";
        }
      '';

      virtualHosts = lib.genAttrs cfg.serverNames (name: {
        extraConfig = ''
          # Using a variable for the upstream endpoint to ensure that it is
          # resolved at runtime as opposed to once when the config file is loaded
          # and then cached forever (we don't want that):
          # see https://tenzer.dk/nginx-with-dynamic-upstreams/
          # This fixes errors like
          #   nginx: [emerg] host not found in upstream "upstream.example.com"
          # when the upstream host is not reachable for a short time when
          # nginx is started.
          set $upstream_endpoint https://cache.nixos.org;
        '';

        locations."/" = {
          proxyPass = "$upstream_endpoint";
          recommendedProxySettings = false;
          extraConfig = ''
            proxy_cache ${cacheName};
            proxy_cache_valid  200 302  60d;
            proxy_set_header Host "cache.nixos.org";
            proxy_ssl_name                cache.nixos.org;
            proxy_ssl_server_name         on;
            proxy_ssl_verify              on;
            proxy_ssl_verify_depth        5;
            proxy_ssl_trusted_certificate /etc/ssl/certs/ca-bundle.crt;
            expires max;
            add_header Cache-Control  $nixos_proxy_cache_control always;
            add_header X-Cache-Status $upstream_cache_status;
          '';
        };
      });
    };

    systemd = {
      services.nginx.serviceConfig.ReadWritePaths = [ cfg.storageDir ];

      tmpfiles.rules = [
        "d ${cfg.storageDir} 0755 ${nginxUser} ${nginxGroup} - -"
      ];
    };
  };

}
