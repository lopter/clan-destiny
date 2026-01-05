{ lib, self, ... }:
let
  inherit (self.lib) diskById diskPart;

  nvmeSSD = "/dev/disk/by-id/nvme-AirDisk_1TB_SSD_NF2015R000469P110N";

  # https://wiki.archlinux.org/title/Dm-crypt/Specialties#Discard/TRIM_support_for_solid_state_drives_(SSD)
  # https://wiki.archlinux.org/title/Dm-crypt/Specialties#Disable_workqueue_for_increased_solid_state_drive_(SSD)_performance
  #
  # Turn those two to true on bare-metal, we're ok with the security
  # implications:
  allowDiscards = true;
  bypassWorkqueues = true;

  keyDrive = "/dev/disk/by-id/usb-SanDisk_Cruzer_Fit_4C530001190616105345-0:0";

  # cryptsetup open --key-file /dev/disk/by-id/usb-SanDisk_Cruzer_Fit*\:0 --keyfile-size 4096 ${nvmeSSD} jellicent-luks
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
      name = "zpool-storage-${driveBayNo}";
      value = {
        type = "disk";
        device = diskById deviceId;
        content = {
          type = "gpt";
          partitions = {
            zfs = {
              label = "jellicent-zpool-storage-${driveBayNo}";
              start = "8M";
              content = {
                type = "zfs";
                pool = "jellicent-storage";
              };
            };
          };
        };
      };
    };

  zfsDevices = lib.mapAttrs' mkZfsDisk {
    "1" = "ata-ST4000VN008-2DR166_ZDH3BBFN";
    "2" = "ata-ST4000VN006-3CW104_WW65RGP8";
  };

  zfsKeysDir = "/run/zfs-keys";
in
{
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
              label = "jellicent-swap";
              content = {
                type = "swap";
                discardPolicy = "both";
                randomEncryption = true;
              };
            };
            luks = {
              priority = 3;
              size = "100%";
              label = "jellicent-luks-system";
              content = {
                name = "jellicent-system";
                type = "luks";
                settings = luksSettings { isSSD = true; };
                content = {
                  type = "btrfs";
                  extraArgs = [
                    "--metadata" "single"
                    "--checksum" "xxhash"
                    "--features" "${lib.concatStringsSep "," [ "block-group-tree" ]}"
                    "--force"
                  ];
                  subvolumes = {
                    "root" = {
                      mountpoint = "/";
                      mountOptions = lib.optionals allowDiscards [ "discard=async" ];
                    };
                    "var" = {
                      mountpoint = "/var";
                      mountOptions = [
                        "nodev"
                        "nosuid"
                      ] ++ lib.optionals allowDiscards [ "discard=async" ];
                    };
                    "stash" = {
                      mountpoint = "/stash";
                      mountOptions = [
                        "nodev"
                        "nosuid"
                      ] ++ lib.optionals allowDiscards [ "discard=async" ];
                    };
                    "nix" = {
                      mountpoint = "/nix";
                      mountOptions = [
                        "noatime"
                        "nodev"
                        "nosuid"
                      ] ++ lib.optionals allowDiscards [ "discard=async" ];
                    };
                    "tmp" = {
                      mountpoint = "/tmp";
                      mountOptions = [
                        "nodev"
                        "nosuid"
                      ] ++ lib.optionals allowDiscards [ "discard=async" ];
                    };
                  };
                };
              };
            };
          };
        };
      };
    } // zfsDevices;
    zpool = {
      jellicent-storage = {
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
                  "/dev/disk/by-partlabel/jellicent-zpool-storage-1"
                  "/dev/disk/by-partlabel/jellicent-zpool-storage-2"
                ];
              }
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
          keylocation = "file://${zfsKeysDir}/zpool-jellicent-storage.key";
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
    };
  };

  boot.initrd = {
    luks.devices = {
      "jellicent-system" = (luksSettings { isSSD = true; }) // {
        device = self.lib.diskPart 3 nvmeSSD;
      };
    };
    supportedFilesystems.btrfs = true;
    supportedFilesystems.zfs = true;
  };

  fileSystems =
  let
    jellicentSystemVolume = { name, options ? [ ] }: {
      device = "/dev/mapper/jellicent-system";
      fsType = "btrfs";
      options =
        [ "subvol=${name}" ]
        ++ options
        ++ lib.optionals allowDiscards [ "discard=async" ];
    };
    mkHomeFs = user: lib.nameValuePair "/stash/home/${user}" {
      device = "jellicent-storage/home/${user}";
      fsType = "zfs";
    };
    familyUsers = builtins.attrNames self.inputs.destiny-config.lib.usergroups.familyUsers;
    homeDirs = lib.genAttrs' familyUsers mkHomeFs;
  in
  homeDirs // {
    "/" = jellicentSystemVolume {
      name = "root";
    };
    "/boot" = {
      device = self.lib.diskPart 1 nvmeSSD;
      fsType = "vfat";
      options = [ "umask=077" ] ++ lib.optionals allowDiscards [ "discard" ];
    };
    ${zfsKeysDir} = {
      device = diskPart 1 keyDrive;
      fsType = "vfat";
      options = [ "ro" "umask=077" ];
      # Note sure we really need that in stage-1, since scylla-goinfre only
      # hosts data, and not something needed by the system, but it will at
      # least make sure it's mounted when it's time to open scylla-goinfre.
      neededForBoot = true;
    };
    "/var" = jellicentSystemVolume {
      name = "var";
      options = [ "nodev" "nosuid" ];
    };
    "/stash" = jellicentSystemVolume {
      name = "stash";
      options = [ "nodev" "nosuid" ];
    };
    "/nix" = jellicentSystemVolume {
      name = "nix";
      options = [ "noatime" "nodev" "nosuid" ];
    };
    "/tmp" = jellicentSystemVolume {
      name = "tmp";
      options = [ "nodev" "nosuid" ];
    };
    "/stash/goinfre" = {
      device = "jellicent-storage/goinfre";
      fsType = "zfs";
    };
    "/stash/home" = {
      device = "jellicent-storage/home";
      fsType = "zfs";
    };
  };

  systemd.tmpfiles.rules = [
    "d /tmp 1777 root root 4w"
  ];

  swapDevices = [
    ({
      device = self.lib.diskPart 2 nvmeSSD;
      randomEncryption = {
        inherit allowDiscards;
        enable = true;
      };
    } // lib.optionalAttrs allowDiscards {
      discardPolicy = "both";
    })
  ];
}
