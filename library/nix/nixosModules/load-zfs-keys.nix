{ config, lib, ... }:
let
  cfg = config.clan-destiny.load-zfs-keys;
in
{
  options.clan-destiny.load-zfs-keys = {
    enable = lib.mkEnableOption "Setup an initrd service to make ZFS decryption keys available";
    zpools = lib.mkOption {
      description = "The list of zpools that depends on this";
      type = with lib.types; nonEmptyListOf nonEmptyStr;
    };
    device = lib.mkOption {
      description = "The FAT formatted block device to mount";
      type = lib.types.path;
      example = "/dev/disk/by-id/usb-USB_FooBar-0:0-part1";
    };
    dir = lib.mkOption {
      description = "The mountpoint for `keyDevice`";
      type = lib.types.path;
      default = "/run/zfs-keys";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.boot.initrd.systemd.enable;
        message = "load-zfs-keys depends on `boot.initrd.systemd`";
      }
    ];

    boot.initrd = {
      kernelModules = [ "vfat" "nls_cp437" "nls_iso8859_1" ];
      supportedFilesystems.zfs = true;
      # no idea how we could get this to work with lanzaboote:
      systemd.services.load-zfs-keys =
      let
        # maybe we could introspect that?
        zfsImportServices = map (zpool: "zfs-import-${zpool}.service") cfg.zpools;
      in
      {
        before = zfsImportServices;
        wantedBy = zfsImportServices;
        wants = [ "systemd-udev-settle.service" ];
        after = [ "systemd-udev-settle.service" ];
        unitConfig = {
          DefaultDependencies = "no";
        };
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          StandardOutput = "journal+console";
        };
        # barebone script since initrd is a different nix store:
        script = ''
          set -euo pipefail

          KEY_DRIVE=${lib.escapeShellArg cfg.device}
          KEY_DIR=${lib.escapeShellArg cfg.dir}

          if ! [ -e "$KEY_DRIVE" ]; then
            printf "load-zfs-keys: checking for %s" "$KEY_DRIVE"
            until [ -e "$KEY_DRIVE" ]; do
              /bin/sleep 2
              printf "."
            done
            printf " done\n"
          fi

          /bin/mkdir -p "$KEY_DIR"
          /bin/mount -o ro,umask=377 "$KEY_DRIVE" "$KEY_DIR"
        '';
      };
    };
  };
}
