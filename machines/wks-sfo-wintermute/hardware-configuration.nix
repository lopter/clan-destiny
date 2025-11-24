{
  lib,
  pkgs,
  ...
}:
let
  quietFans = pkgs.writeShellApplication {
    name = "quiet-fans";
    runtimeInputs = [ pkgs.fd pkgs.coreutils ];
    text = ''
      PWM="''${1-100}"
      if [[ ! "$PWM" =~ ^[0-9]+$ ]] || (( PWM < 0 || PWM > 255 )) ; then
          printf "Invalid: must be a number between 0 and 255, got: %s\n" "$PWM"
          exit 1
      fi

      # See https://www.kernel.org/doc/html/latest/hwmon/nct6775.html
      PWM_ENABLE_MANUAL_MODE=1
      DEVICE="$(fd -p '^.+nct6775.+hwmon[0-9]+$' /sys/devices)"

      cd "$DEVICE"

      for p in pwm?_enable ; do
        echo "$PWM_ENABLE_MANUAL_MODE" >"$p"
      done

      sleep 5

      for p in pwm? ; do
        echo "$PWM" >"$p"
      done
    '';
  };
in
{
  boot.initrd.availableKernelModules = [ "xhci_pci" "ahci" "nvme" "usb_storage" "uas" "usbhid" "sd_mod" "sr_mod" ];
  boot.initrd.kernelModules = [ "dm-snapshot" ];
  boot.kernelModules = [ "kvm-amd" "nct6775" ];

  nixpkgs.hostPlatform = lib.mkForce "x86_64-linux";

  environment.systemPackages = [ quietFans ];

  hardware.fancontrol.enable = true;
}
