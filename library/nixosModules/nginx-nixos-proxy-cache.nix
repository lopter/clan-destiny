{ config, lib, ... }:
let
  cfg = config.clan-destiny.nginx.nixos-proxy-cache;
  nginxCfg = config.clan.clan-destiny.services.nginx;

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
    serverName = lib.mkOption {
      type = lib.types.nonEmptyStr;
      description = "Name of the http virtual host for the cache.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [{
      assertion = builtins.length config.services.nginx.resolver.addresses > 0;
      message = ''
        `clan-destiny.nginx.nixos-proxy-cache` requires
        `services.nginx.resolvers` to be set.
      '';
    }];

    services.nginx = {
      enable = true;
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
      
      virtualHosts."${cfg.serverName}" = {
        extraConfig = ''
          # Using a variable for the upstream endpoint to ensure that it is
          # resolved at runtime as opposed to once when the config file is loaded
          # and then cached forever (we don't want that):
          # see https://tenzer.dk/nginx-with-dynamic-upstreams/
          # This fixes errors like
          #   nginx: [emerg] host not found in upstream "upstream.example.com"
          # when the upstream host is not reachable for a short time when
          # nginx is started.
          set $upstream_endpoint http://cache.nixos.org;
        '';

        locations."/" = {
          proxyPass = "$upstream_endpoint";
          recommendedProxySettings = false;
          extraConfig = ''
            proxy_cache ${cacheName};
            proxy_cache_valid  200 302  60d;
            proxy_set_header Host "cache.nixos.org";
            expires max;
            add_header Cache-Control $nixos_proxy_cache_control always;
          '';
        };
      };
    };

    systemd = {
      services.nginx.serviceConfig.ReadWritePaths = [ cfg.storageDir ];

      tmpfiles.rules = [
        "d ${cfg.storageDir} 0755 ${nginxCfg.user} ${nginxCfg.group} - -"
      ];
    };
  };

}
