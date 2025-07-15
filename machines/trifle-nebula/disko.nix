{ lib, ... }:
let
  nvmeSSD = "/dev/disk/by-id/nvme-Samsung_SSD_990_PRO_with_Heatsink_2TB_S7HGNJ0Y415850E";
  # https://wiki.archlinux.org/title/Dm-crypt/Specialties#Discard/TRIM_support_for_solid_state_drives_(SSD)
  # https://wiki.archlinux.org/title/Dm-crypt/Specialties#Disable_workqueue_for_increased_solid_state_drive_(SSD)_performance
  #
  # Turn those two to true on bare-metal, we're ok with the security
  # implications:
  allowDiscards = true;
  bypassWorkqueues = true;

  luksSettings = {
    inherit allowDiscards bypassWorkqueues;
    # Do that until we can manually add a passphrase or do secure boot with
    # a fingerprint:
    keyFileSize = 4096;
    keyFileOffset = 64 * 1024;
    keyFile = "/dev/disk/by-id/usb-SanDisk_Cruzer_Fit_4C530001090616105200-0:0";
  };
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
        device = nvmeSSD;
        content = {
          type = "gpt";
          partitions = {
            ESP = {
              priority = 1;
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
              size = "96G";
              content = {
                type = "swap";
                randomEncryption = true;
              };
            };
            luks = {
              priority = 3;
              size = "100%";
              label = "trifle-nebula-luks-system";
              content = {
                name = "trifle-nebula-system";
                type = "luks";
                settings = luksSettings;
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
                        "noatime"
                      ] ++ lib.optionals allowDiscards [ "discard=async" ];
                    };
                    "stash" = {
                      mountpoint = "/stash";
                      mountOptions = [
                        "nodev"
                        "nosuid"
                        "noatime"
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
                        "noatime"
                      ] ++ lib.optionals allowDiscards [ "discard=async" ];
                    };
                  };
                };
              };
            };
          };
        };
      };
    };
  };

  boot.initrd = {
    luks.devices."trifle-nebula-system" = luksSettings // {
      device = "${nvmeSSD}-part3";
    };
    supportedFilesystems.btrfs = true;
  };

  fileSystems =
  let
    trifleNebulaSystemVolume = { name, options ? [ ] }: {
      device = "/dev/mapper/trifle-nebula-system";
      fsType = "btrfs";
      options =
        [ "subvol=${name}" ]
        ++ options
        ++ lib.optionals allowDiscards [ "discard=async" ];
    };
  in
  {
    "/" = trifleNebulaSystemVolume {
      name = "root";
    };
    "/boot" = {
      device = "${nvmeSSD}-part1";
      fsType = "vfat";
      options = [ "umask=077" ] ++ lib.optionals allowDiscards [ "discard" ];
    };
    "/var" = trifleNebulaSystemVolume {
      name = "var";
      options = [ "nodev" "nosuid" ];
    };
    "/stash" = trifleNebulaSystemVolume {
      name = "stash";
      options = [ "nodev" "nosuid" ];
    };
    "/nix" = trifleNebulaSystemVolume {
      name = "nix";
      options = [ "noatime" "nodev" "nosuid" ];
    };
    "/tmp" = trifleNebulaSystemVolume {
      name = "tmp";
      options = [ "nodev" "nosuid" ];
    };
  };

  systemd.tmpfiles.rules = [
    "d /tmp 1777 root root 4w"
  ];

  swapDevices = [
    ({
      device = "${nvmeSSD}-part2";
      randomEncryption = {
        inherit allowDiscards;
        enable = true;
      };
    } // lib.optionalAttrs allowDiscards {
      discardPolicy = "both";
    })
  ];
}
