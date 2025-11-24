{ config, lib, pkgs, self, ... }:
let
  inherit (self.lib) diskById diskPart;
  inherit (config.networking) hostName;

  nvmeSSD = diskById "nvme-Samsung_SSD_960_PRO_1TB_S3EVNX0J802801W";

  # https://wiki.archlinux.org/title/Dm-crypt/Specialties#Discard/TRIM_support_for_solid_state_drives_(SSD)
  # https://wiki.archlinux.org/title/Dm-crypt/Specialties#Disable_workqueue_for_increased_solid_state_drive_(SSD)_performance
  #
  # Turn those two to true on bare-metal, we're ok with the security
  # implications:
  allowDiscards = true;
  bypassWorkqueues = true;

  keyDrive = diskById "usb-USB_SanDisk_3.2Gen1_03023327042524070528-0:0";

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

  mkZfsDisk =
    deviceId: deviceCfg:
    let
      inherit (deviceCfg) zpoolName;
      driveBayNo = lib.optionalString (deviceCfg ? driveBayNo) "-${deviceCfg.driveBayNo}";
      hostId = lib.lists.last (builtins.split "-" hostName);
    in
    {
      name = "zpool-${zpoolName}${driveBayNo}";
      value = {
        type = "disk";
        device = diskById deviceId;
        content = {
          type = "gpt";
          partitions = {
            zfs = {
              label = "zpool-${hostId}-${zpoolName}${driveBayNo}";
              start = "8M";
              content = {
                type = "zfs";
                pool = "${hostId}-${zpoolName}";
              };
            };
          };
        };
      };
    };

  zfsDevices = lib.mapAttrs' mkZfsDisk {
  };

  zfsKeysDir = "/run/zfs-keys";
in
{
  # Note that using `enableConfig = false` and `legacy` ZFS mount points means
  # that `clan install` needs to be done in steps: the disko phase first, then
  # manually mount everything under `/mnt`, and finally the install phase.
  disko.enableConfig = false;
  disko.devices = {
    disk = {
      system = {
        type = "disk";
        device = nvmeSSD;
        content = {
          type = "gpt";
          partitions = {
            ESP = {
              priority = 1;
              start = "1M";
              size = "1G";
              type = "EF00";
              label = "wintermute-boot";
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
              label = "wintermute-swap";
              content = {
                type = "swap";
                discardPolicy = "both";
                randomEncryption = true;
              };
            };
            zfs = {
              priority = 3;
              size = "100%";
              label = "wintermute-zpool-system";
              content = {
                type = "zfs";
                pool = "wintermute-system";
              };
            };
          };
        };
      };
    } // zfsDevices;
    zpool = {
      wintermute-system = {
        type = "zpool";
        rootFsOptions = ZfsBaseRootFsOptions // {
          keylocation = "file://${zfsKeysDir}/zpool-wintermute-system.key";
        };
        options = {
          ashift = "12";
          autotrim = "on";
        };
        datasets = {
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
          home-kal = {
            type = "zfs_fs";
            options = {
              "com.sun:auto-snapshot" = "true";
              devices = "off";
              setuid = "off";
            };
          };
        };
      };
      /*
      wintermute-storage = {
        type = "zpool";
        mode = {
          topology = {
            type = "topology";
            vdev = [
              {
                mode = "mirror";
                # Looks like there is [some assumptions] on how members are
                # expressed so we gotta give absolute device paths:
                #
                # [some assumptions]: https://github.com/nix-community/disko/blob/ff3568858c54bd306e9e1f2886f0f781df307dff/lib/types/zpool.nix#L238
                members = [
                  "/dev/disk/by-partlabel/wintermute-zpool-storage-1"
                  "/dev/disk/by-partlabel/wintermute-zpool-storage-2"
                ];
              }
            ];
          };
        };
        rootFsOptions = {
          acltype = "posix";
          aclmode = "passthrough";
          atime = "on";
          compression = "zstd";
          "com.sun:auto-snapshot" = "false";
          encryption = "on";
          keyformat = "passphrase";
          keylocation = "file://${zfsKeysDir}/zpool-wintermute-storage.key";
          # Use legacy since we'll use the fileSystems option to mount the zfs
          # datasets (see note in `boot.zfs.extraPools`):
          mountpoint = "legacy";
          relatime = "on"; # effective when atime=on
          xattr = "sa";
        };
        options = {
          ashift = "12";
          "feature@lz4_compress" = "enabled";
          "feature@raidz_expansion" = "enabled";
        };
        datasets = {
          goinfre = {
            type = "zfs_fs";
            options.recordsize = "1M";
            options."com.sun:auto-snapshot" = "true";
          };
          home = {
            type = "zfs_fs";
            options.recordsize = "16K";
            options."com.sun:auto-snapshot" = "true";
          };
        };
      };
      */
    };
  };

  boot.initrd = {
    # modules needed by load-zfs-keys service below:
    kernelModules = [ "vfat" "nls_cp437" "nls_iso8859_1" ];
    supportedFilesystems.zfs = true;
    # no idea how we could get this to work with lanzaboote:
    systemd.services.load-zfs-keys = {
      before = [ "zfs-import-wintermute-system.service" ];
      wantedBy = [ "zfs-import-wintermute-system.service" ];
      serviceConfig = {
        Type = "oneshot";
        # barebone script since initrd is a different nix store:
        ExecStart = ''/bin/bash -c " \
          if [ ! -d ${zfsKeysDir} ] ; then \
            /bin/mkdir ${zfsKeysDir} \
            && /bin/mount -o ro,umask=377 ${diskPart 1 keyDrive} ${zfsKeysDir} ; \
          fi \
        "'';
      };
    };
  };
  boot.zfs.devNodes = "/dev/disk/by-id";

  fileSystems =
  {
    "/" = {
      device = "wintermute-system/root";
      fsType = "zfs";
    };
    "/boot" = {
      device = diskPart 1 nvmeSSD;
      fsType = "vfat";
      options = [ "umask=077" ] ++ lib.optionals allowDiscards [ "discard" ];
    };
    # Even with `neededForBoot` this still gets mounted to late:
    # ${zfsKeysDir} = {
    #   device = diskPart 1 keyDrive;
    #   fsType = "vfat";
    #   options = [ "ro" "umask=377" ];
    #   neededForBoot = true;
    # };
    "/var" = {
      device = "wintermute-system/var";
      fsType = "zfs";
    };
    "/nix" = {
      device = "wintermute-system/nix";
      fsType = "zfs";
    };
    "/tmp" = {
      device = "wintermute-system/tmp";
      fsType = "zfs";
    };
    "/stash/home/kal" = {
      device = "wintermute-system/home-kal";
      fsType = "zfs";
    };
    /*
    "/stash/goinfre" = {
      device = "wintermute-storage/goinfre";
      fsType = "zfs";
    };
    */
  };

  systemd.tmpfiles.rules = [
    "d /tmp 1777 root root 4w"
  ];

  swapDevices = [
    ({
      device = diskPart 2 nvmeSSD;
      randomEncryption = {
        inherit allowDiscards;
        enable = true;
      };
    } // lib.optionalAttrs allowDiscards {
      discardPolicy = "both";
    })
  ];
}

