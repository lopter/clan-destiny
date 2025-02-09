{ lib, self, ... }:
let
  nvmeSSD = "/dev/disk/by-id/nvme-AirDisk_1TB_SSD_NF2015R000469P110N";

  sataHDD-A = "/dev/disk/by-id/ata-ST16000NM000J-2TW103_ZR701X68";
  sataHDD-B = "/dev/disk/by-id/ata-ST16000NM000J-2TW103_ZR51RHGA";

  # https://wiki.archlinux.org/title/Dm-crypt/Specialties#Discard/TRIM_support_for_solid_state_drives_(SSD)
  # https://wiki.archlinux.org/title/Dm-crypt/Specialties#Disable_workqueue_for_increased_solid_state_drive_(SSD)_performance
  #
  # Turn those two to true on bare-metal, we're ok with the security
  # implications:
  allowDiscards = true;
  bypassWorkqueues = true;

  # cryptsetup open --key-file /dev/disk/by-id/usb-SanDisk_Cruzer_Fit*\:0 --keyfile-size 4096 ${nvmeSSD} jellicent-luks
  luksSettings = { isSSD }: {
    keyFileSize = 4096;
    keyFile = "/dev/disk/by-id/usb-SanDisk_Cruzer_Fit_4C530001190616105345-0:0";
  } // lib.optionalAttrs isSSD {
    inherit allowDiscards bypassWorkqueues;
  };

  luksDataDisk = { label, luksContent ? null }: {
      type = "gpt";
      partitions = {
        luks = {
          start = "8M";
          end = "-8M";
          label = "jellicent-luks-data-${label}";
          content = {
            type = "luks";
            name = "jellicent-data-${label}";
            settings = luksSettings { isSSD = false; };
          } // lib.optionalAttrs (luksContent != null) {
            content = luksContent;
          };
        };
      };
  };

  commonMkfsBtrfsOptions = [
    "--checksum" "xxhash"
    "--features" "${lib.concatStringsSep "," [ "block-group-tree" ]}"
    "--force"
  ];
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
                  extraArgs = commonMkfsBtrfsOptions;
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
      data-A = {
        type = "disk";
        device = sataHDD-A;
        content = luksDataDisk { label = "A"; };
      };
      data-B = {
        type = "disk";
        device = sataHDD-B;
        content = luksDataDisk {
          label = "B";
          luksContent = {
            type = "btrfs";
            extraArgs = commonMkfsBtrfsOptions ++ [
              "--data" "raid1"
              "/dev/mapper/jellicent-data-A"
            ];
            subvolumes = {
              goinfre = {
                mountpoint = "/stash/goinfre";
                mountOptions = [ "nodev" "nosuid" ];
              };
            };
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
      "jellicent-data-A" = (luksSettings { isSSD = false; }) // {
        device = self.lib.diskPart 1 sataHDD-A;
      };
      "jellicent-data-B" = (luksSettings { isSSD = false; }) // {
        device = self.lib.diskPart 1 sataHDD-B;
      };
    };
    supportedFilesystems.btrfs = true;
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
  in
  {
    "/" = jellicentSystemVolume {
      name = "root";
    };
    "/boot" = {
      device = self.lib.diskPart 1 nvmeSSD;
      fsType = "vfat";
      options = [ "umask=077" ] ++ lib.optionals allowDiscards [ "discard" ];
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
      device = "/dev/mapper/jellicent-data-A";
      fsType = "btrfs";
      options = [
        "subvol=goinfre"
        "nodev"
        "nosuid"
      ];
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
