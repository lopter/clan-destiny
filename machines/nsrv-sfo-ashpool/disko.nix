{ lib, ... }:
let
  # Get the partition of the given number for the given storage device. Expand
  # to the correct path whether devices are addressed using /dev/disk/by- or
  # using something of the like of /dev/sda:
  diskPart =
    number: diskName:
    if builtins.isList (builtins.match ".+by-(id|uuid).+" diskName) then
      "${diskName}-part${toString number}"
    else
      "${diskName}${toString number}";

  sataSSD = "/dev/disk/by-id/ata-Samsung_SSD_870_EVO_4TB_S6P3NS0W300955A";
  # https://wiki.archlinux.org/title/Dm-crypt/Specialties#Discard/TRIM_support_for_solid_state_drives_(SSD)
  # https://wiki.archlinux.org/title/Dm-crypt/Specialties#Disable_workqueue_for_increased_solid_state_drive_(SSD)_performance
  #
  # Turn those two to true on bare-metal, we're ok with the security
  # implications:
  allowDiscards = true;
  bypassWorkqueues = true;

  # cryptsetup open --key-file /dev/disk/by-id/usb-USB_SanDisk_3.2Gen1_*\:0 --keyfile-size 4096 /dev/vda3 ashpool-luks
  luksSettings = {
    inherit allowDiscards bypassWorkqueues;
    # Do that until we can manually add a passphrase or do secure boot with
    # a fingerprint:
    keyFileSize = 4096;
    keyFile = "/dev/disk/by-id/usb-USB_SanDisk_3.2Gen1_03022020042524070315-0:0";
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
        device = sataSSD;
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
              size = "32G";
              content = {
                type = "swap";
                randomEncryption = true;
              };
            };
            luks = {
              priority = 3;
              size = "100%";
              content = {
                name = "ashpool-luks";
                type = "luks";
                settings = luksSettings;
                content = {
                  type = "lvm_pv";
                  vg = "vgAshpoolSystem";
                };
              };
            };
          };
        };
      };
    };
    lvm_vg = {
      vgAshpoolSystem = {
        type = "lvm_vg";
        lvs = {
          lvRoot = {
            size = "1G";
            content = {
              type = "filesystem";
              format = "ext4";
              mountpoint = "/";
              mountOptions = [
                "nodev"
                "nosuid"
              ] ++ lib.optionals allowDiscards [ "discard" ];
            };
          };
          # Having different volumes imposes some hard quotas:
          lvVar = {
            size = "20G";
            content = {
              type = "filesystem";
              format = "ext4";
              mountpoint = "/var";
              mountOptions = [
                "nodev"
                "nosuid"
              ] ++ lib.optionals allowDiscards [ "discard" ];
            };
          };
          lvStash = {
            size = "3T";
            content = {
              type = "filesystem";
              format = "ext4";
              mountpoint = "/stash";
              mountOptions = [
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
                "noatime"
                "nodev"
                "nosuid"
              ] ++ lib.optionals allowDiscards [ "discard" ];
            };
          };
        };
      };
    };
  };

  boot.initrd.luks.devices."ashpool-system" = luksSettings // {
    device = diskPart 3 sataSSD;
  };

  fileSystems = {
    "/" =
      let
        maybeOptions = if allowDiscards then { options = [ "discard" ]; } else { };
      in
      {
        device = "/dev/vgAshpoolSystem/lvRoot";
        fsType = "ext4";
      }
      // maybeOptions;
    "/boot" = {
      device = diskPart 1 sataSSD;
      fsType = "vfat";
      options = [ "umask=077" ] ++ lib.optionals allowDiscards [ "discard" ];
    };
    "/var" = {
      device = "/dev/vgAshpoolSystem/lvVar";
      fsType = "ext4";
      options = [
        "nodev"
        "nosuid"
      ] ++ lib.optionals allowDiscards [ "discard" ];
    };
    "/stash" = {
      device = "/dev/vgAshpoolSystem/lvStash";
      fsType = "ext4";
      options = [
        "nodev"
        "nosuid"
      ] ++ lib.optionals allowDiscards [ "discard" ];
    };
    "/nix" = {
      device = "/dev/vgAshpoolSystem/lvNix";
      fsType = "ext4";
      options = [
        "noatime"
        "nodev"
        "nosuid"
      ] ++ lib.optionals allowDiscards [ "discard" ];
    };
    "/tmp" = {
      device = "/dev/vgAshpoolSystem/lvTmp";
      fsType = "ext4";
      options = [
        "noatime"
        "nodev"
        "nosuid"
      ] ++ lib.optionals allowDiscards [ "discard" ];
    };
  };

  systemd.tmpfiles.rules = [
    "d /tmp 1777 root root 4w"
  ];

  swapDevices = [
    {
      device = diskPart 2 sataSSD;
      randomEncryption = {
        inherit allowDiscards;
        enable = true;
      };
      discardPolicy = null;
    }
  ];
}
