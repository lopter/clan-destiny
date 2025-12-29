{ config, lib, self, ... }:
let
  inherit (self.lib) diskById diskPart;
  inherit (config.networking) hostName;

  hostId = lib.lists.last (builtins.split "-" hostName);

  sataSSD = "/dev/disk/by-id/ata-Samsung_SSD_870_EVO_4TB_S6P3NS0W300955A";

  # https://wiki.archlinux.org/title/Dm-crypt/Specialties#Discard/TRIM_support_for_solid_state_drives_(SSD)
  # https://wiki.archlinux.org/title/Dm-crypt/Specialties#Disable_workqueue_for_increased_solid_state_drive_(SSD)_performance
  #
  # Turn those two to true on bare-metal, we're ok with the security
  # implications:
  allowDiscards = true;

  keyDrive = diskById "usb-USB_SanDisk_3.2Gen1_03022020042524070315-0:0";
  zfsKeysDir = config.clan-destiny.load-zfs-keys.dir;

  ZfsBaseRootFsOptions = {
    acltype = "posix";
    aclmode = "passthrough";
    atime = "off";
    compression = "zstd";
    "com.sun:auto-snapshot" = "false";
    encryption = "on";
    keyformat = "passphrase";
    # Use legacy since we'll use the fileSystems option to mount the zfs
    # datasets (see note in `boot.zfs.extraPools`):
    mountpoint = "legacy";
    relatime = "on"; # effective when atime=on
    xattr = "sa";
    dnodesize = "auto";
  };

  familyUsers = builtins.attrNames self.inputs.destiny-config.lib.usergroups.familyUsers;
in
{
  # Do not let Disko manage fileSystems.* config for NixOS.
  # Reason is that Disko mounts partitions by GPT partition names, which are
  # easily overwritten with tools like fdisk. When you fail to deploy a new
  # config in this case, the old config that comes with the disk image will
  # not boot either.
  disko.enableConfig = false;

  disko.devices = {
    disk = {
      system = {
        type = "disk";
        device = sataSSD;
        content = {
          type = "gpt";
          partitions = {
            ESP = {
              priority = 1;
              size = "1G";
              type = "EF00";
              label = "${hostId}-boot";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
                mountOptions = [ "umask=077" ] ++ lib.optionals allowDiscards [ "discard" ];
              };
            };
            swap = {
              priority = 2;
              size = "32G";
              label = "${hostId}-swap";
              content = {
                type = "swap";
                discardPolicy = "both";
                randomEncryption = true;
              };
            };
            zfs = {
              priority = 3;
              size = "100%";
              label = "${hostId}-zpool-system";
              content = {
                type = "zfs";
                pool = "${hostId}-system";
              };
            };
          };
        };
      };
    };
    zpool = {
      "${hostId}-system" = {
        type = "zpool";
        rootFsOptions = ZfsBaseRootFsOptions // {
          keylocation = "file://${zfsKeysDir}/zpool-${hostId}-system.key";
        };
        options = {
          ashift = "12";
          autotrim = "on";
        };
        datasets =
        let
          mkHomeDataset = user: lib.nameValuePair "home/${user}" {
            type = "zfs_fs";
            options = {
              "com.sun:auto-snapshot" = "true";
              devices = "off";
              setuid = "off";
            };
          };
          homeDatasets = lib.genAttrs' familyUsers mkHomeDataset;
        in
        homeDatasets // {
          root.type = "zfs_fs";
          nix = {
            type = "zfs_fs";
            options = {
              devices = "off";
              setuid = "off";
            };
          };
          var = {
            type = "zfs_fs";
            options = {
              devices = "off";
              setuid = "off";
            };
          };
          tmp = {
            type = "zfs_fs";
            options = {
              devices = "off";
              setuid = "off";
            };
          };
          stash = {
            type = "zfs_fs";
            options = {
              "com.sun:auto-snapshot" = "true";
              devices = "off";
              setuid = "off";
            };
          };
          home = {
            type = "zfs_fs";
            options = {
              "com.sun:auto-snapshot" = "true";
              devices = "off";
              setuid = "off";
              canmount = "off";
            };
          };
        };
      };
    };
  };

  clan-destiny.load-zfs-keys = {
    enable = true;
    device = diskPart 1 keyDrive;
    zpools = [ "${hostId}-system" ];
  };

  boot.zfs.devNodes = "/dev/disk/by-id";

  fileSystems =
  let
    mkHomeFs = user: lib.nameValuePair "/stash/home/${user}" {
      device = "${hostId}-system/home/${user}";
      fsType = "zfs";
    };
    homeDirs = lib.genAttrs' familyUsers mkHomeFs;
  in
  homeDirs // {
    "/" = {
      device = "${hostId}-system/root";
      fsType = "zfs";
    };
    "/boot" = {
      device = self.lib.diskPart 1 sataSSD;
      fsType = "vfat";
      options = [ "umask=077" ] ++ lib.optionals allowDiscards [ "discard" ];
    };
    "/var" = {
      device = "${hostId}-system/var";
      fsType = "zfs";
    };
    "/nix" = {
      device = "${hostId}-system/nix";
      fsType = "zfs";
    };
    "/tmp" = {
      device = "${hostId}-system/tmp";
      fsType = "zfs";
    };
    "/stash" = {
      device = "${hostId}-system/stash";
      fsType = "zfs";
    };
  };

  systemd.tmpfiles.rules = [
    "d /tmp 1777 root root 4w"
  ];

  swapDevices = [
    ({
      device = self.lib.diskPart 2 sataSSD;
      randomEncryption = {
        inherit allowDiscards;
        enable = true;
      };
    } // lib.optionalAttrs allowDiscards {
      discardPolicy = "both";
    })
  ];
}
