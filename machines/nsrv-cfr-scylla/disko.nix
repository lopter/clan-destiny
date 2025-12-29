{ lib, self, ... }:
let
  inherit (self.lib) diskById diskPart;

  sataSSD = diskById "ata-Samsung_SSD_860_EVO_500GB_S3Z2NB0K761518B"; # bay 5

  keyDrive = diskById "usb-SanDisk_Cruzer_Fit_4C530001070616105200-0:0";

  allowDiscards = true;
  bypassWorkqueues = true;

  # USB drive setup to hold the keys:
  #
  # DEVICE=/dev/sda
  # MOUNT_POINT=mnt
  # sgdisk -n 1:1M:17M -t 1:0b00 -c 1:"scylla-zfs-keys" $DEVICE
  # mkfs.vfat -F 32 ${DEVICE}1
  # mount ${DEVICE}1 $MOUNT_POINT
  # pushd $MOUNT_POINT
  # xkcdpass -n 8
  # python -c "import getpass; fp = open('goinfre.key', 'w'); fp.write(getpass.getpass()); fp.close()"
  # popd
  # umount $MOUNT_POINT
  # dd if=/dev/random of=$DEVICE bs=4096 count=1 seek=$((1024 * 64 / 4096)) conv=fsync status=progress
  luksSettings = { isSSD }: {
    keyFileSize = 4096;
    keyFileOffset = 64 * 1024;
    keyFile = keyDrive;
  } // lib.optionalAttrs isSSD {
    inherit allowDiscards bypassWorkqueues;
  };

  mkZfsDisk =
    driveBayNo: deviceId: # driveBayNo is labeled on each drive's tray
    {
      name = "zpool-goinfre-${driveBayNo}";
      value = {
        type = "disk";
        device = diskById deviceId;
        content = {
          type = "gpt";
          partitions = {
            zfs = {
              label = "scylla-zpool-goinfre-${driveBayNo}";
              start = "8M";
              content = {
                type = "zfs";
                pool = "zpool-goinfre";
              };
            };
          };
        };
      };
    };

  zfsDevices = lib.mapAttrs' mkZfsDisk {
    "1" = "ata-ST4000VN008-2DR166_ZGY1Q23P";
    "2" = "ata-ST4000VN006-3CW104_WW65N3WC";
    "3" = "ata-ST4000VN008-2DR166_ZDH3AJFX";
    "4" = "ata-ST4000VN006-3CW104_WW65N4LY";
    "6" = "ata-ST4000VN006-3CW104_WW65RE9Y";
  };

  zfsKeysDir = "/run/zfs-keys";
in
{
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
              start = "1M";
              size = "1G";
              type = "EF00";
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
              label = "scylla-swap";
              content = {
                type = "swap";
                discardPolicy = "both";
                randomEncryption = true;
              };
            };
            luks = {
              priority = 3;
              size = "100%";
              label = "scylla-luks-system";
              content = {
                name = "scylla-luks-system";
                type = "luks";
                settings = luksSettings { isSSD = true; };
                content = {
                  type = "lvm_pv";
                  vg = "vgScyllaSystem";
                };
              };
            };
          };
        };
      };
    } // zfsDevices;
    lvm_vg = {
      vgScyllaSystem = {
        type = "lvm_vg";
        lvs = {
          lvRoot = {
            size = "1G";
            content = {
              type = "filesystem";
              format = "ext4";
              mountpoint = "/";
              mountOptions = [
                "relatime"
                "nodev"
                "nosuid"
              ] ++ lib.optionals allowDiscards [ "discard" ];
            };
          };
          # Having different volumes imposes some hard quotas:
          lvVar = {
            size = "80G";
            content = {
              type = "filesystem";
              format = "ext4";
              mountpoint = "/var";
              mountOptions = [
                "relatime"
                "nodev"
                "nosuid"
              ] ++ lib.optionals allowDiscards [ "discard" ];
            };
          };
          lvStash = {
            size = "100G";
            content = {
              type = "filesystem";
              format = "ext4";
              mountpoint = "/stash";
              mountOptions = [
                "relatime"
                "nodev"
                "nosuid"
              ] ++ lib.optionals allowDiscards [ "discard" ];
            };
          };
          lvNix = {
            size = "100G";
            content = {
              type = "filesystem";
              format = "ext4";
              mountpoint = "/nix";
              mountOptions = [
                "noatime"
                "nodev"
                "nosuid"
              ] ++ lib.optionals allowDiscards [ "discard" ];
            };
          };
          lvTmp = {
            size = "20G";
            content = {
              type = "filesystem";
              format = "ext4";
              mountpoint = "/tmp";
              mountOptions = [
                "relatime"
                "nodev"
                "nosuid"
              ] ++ lib.optionals allowDiscards [ "discard" ];
            };
          };
        };
      };
    };
    zpool = {
      zpool-goinfre = {
        type = "zpool";
        mode = {
          topology = {
            type = "topology";
            vdev = [
              {
                # I meant to use draid2, with only one
                # spare I guess it does not matter…
                mode = "raidz2";
                # Looks like there is [some assumptions] on how members are
                # expressed so we gotta give absolute device paths:
                #
                # [some assumptions]: https://github.com/nix-community/disko/blob/ff3568858c54bd306e9e1f2886f0f781df307dff/lib/types/zpool.nix#L238
                members = [
                  "/dev/disk/by-partlabel/scylla-zpool-goinfre-1"
                  "/dev/disk/by-partlabel/scylla-zpool-goinfre-2"
                  "/dev/disk/by-partlabel/scylla-zpool-goinfre-3"
                  "/dev/disk/by-partlabel/scylla-zpool-goinfre-4"
                ];
              }
            ];
            spare = [
              "/dev/disk/by-partlabel/scylla-zpool-goinfre-6"
            ];
          };
        };
        rootFsOptions = {
          acltype = "posix";
          aclmode = "passthrough";
          atime = "on";
          compression = "lz4";
          "com.sun:auto-snapshot" = "false";
          encryption = "on";
          keyformat = "passphrase";
          keylocation = "file://${zfsKeysDir}/zpool-goinfre.key";
          # Use legacy since we'll use the fileSystems option to mount the zfs
          # datasets (see note in `boot.zfs.extraPools`):
          mountpoint = "legacy";
          recordsize = "1M";
          relatime = "on"; # effective when atime=on
          xattr = "sa";
        };
        options = {
          ashift = "12";
          "feature@lz4_compress" = "enabled";
          "feature@raidz_expansion" = "enabled";
        };
        datasets = {
          root = {
            type = "zfs_fs";
            mountpoint = "legacy";
            options."com.sun:auto-snapshot" = "true";
          };
        };
      };
    };
  };

  boot.initrd = {
    luks.devices."scylla-system" = (luksSettings { isSSD = true; }) // {
      device = diskPart 3 sataSSD;
    };
  };
  boot.supportedFilesystems.zfs = true;

  fileSystems =
  let
    mkHomeFs = user: lib.nameValuePair "/stash/home/${user}" {
      device = "zpool-goinfre/home/${user}";
      fsType = "zfs";
    };
    familyUsers = builtins.attrNames self.inputs.destiny-config.lib.usergroups;
    homeDirs = lib.genAttrs' familyUsers mkHomeFs;
  in
  homeDirs // {
    "/" = {
      device = "/dev/vgScyllaSystem/lvRoot";
      fsType = "ext4";
    } // (lib.optionalAttrs allowDiscards {
      options = [ "discard" ];
    });
    "/boot" = {
      device = diskPart 1 sataSSD;
      fsType = "vfat";
      options = [ "umask=077" ] ++ lib.optionals allowDiscards [ "discard" ];
    };
    ${zfsKeysDir} = {
      device = diskPart 1 keyDrive;
      fsType = "vfat";
      options = [ "ro" "umask=077" ];
      # Note sure we really need that in stage-1, since zpool-goinfre only
      # hosts data, and not something needed by the system, but it will at
      # least make sure it's mounted when it's time to open zpool-goinfre.
      neededForBoot = true;
    };
    "/var" = {
      device = "/dev/vgScyllaSystem/lvVar";
      fsType = "ext4";
      options = [
        "relatime"
        "nodev"
        "nosuid"
      ] ++ lib.optionals allowDiscards [ "discard" ];
    };
    "/stash" = {
      device = "/dev/vgScyllaSystem/lvStash";
      fsType = "ext4";
      options = [
        "relatime"
        "nodev"
        "nosuid"
      ] ++ lib.optionals allowDiscards [ "discard" ];
    };
    "/nix" = {
      device = "/dev/vgScyllaSystem/lvNix";
      fsType = "ext4";
      options = [
        "noatime"
        "nodev"
        "nosuid"
      ] ++ lib.optionals allowDiscards [ "discard" ];
    };
    "/tmp" = {
      device = "/dev/vgScyllaSystem/lvTmp";
      fsType = "ext4";
      options = [
        "relatime"
        "nodev"
        "nosuid"
      ] ++ lib.optionals allowDiscards [ "discard" ];
    };
    "/stash/goinfre" = {
      device = "zpool-goinfre/root";
      fsType = "zfs";
    };
    "/stash/home" = {
      device = "zpool-goinfre/home";
      fsType = "zfs";
    };
    "/stash/photos" = {
      device = "zpool-goinfre/photos";
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
