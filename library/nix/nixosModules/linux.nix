{
  # Make USB thumb drives available during stage 1:
  boot.initrd.availableKernelModules = [ "uas" "usb_storage" ];

  boot.kernel.sysctl = {
    "fs.inotify.max_user_instances" = 256;
    "fs.inotify.max_user_watches" = 100000;
    "net.ipv4.conf.all.rp_filter" = 1;
    "net.ipv4.conf.all.accept_redirects" = 0;
    "net.ipv6.conf.all.accept_redirects" = 0;
  };

  # Make unfree closed-source binary firmwares available to the kernel so that
  # they can be loaded to the devices that need them. This option only enables
  # firmwares with a license that allows them to be redistributed.
  hardware.enableRedistributableFirmware = true;
}
