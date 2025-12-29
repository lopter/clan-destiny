{
  # Make USB thumb drives available during stage 1:
  boot.initrd.availableKernelModules = [
    "uas"
    "usb_storage"
  ];

  boot.kernelModules = [
    "tun"
  ];

  boot.kernel.sysctl = {
    "fs.inotify.max_user_instances" = 256;
    "fs.inotify.max_user_watches" = 524288;
    "net.core.rmem_max" = 7500000;
    "net.core.wmem_max" = 7500000;

    # Reverse path filtering/IP spoofing protection
    "net.ipv4.conf.all.rp_filter" = 1;
    "net.ipv4.conf.default.rp_filter" = 1;

    # Ignore ICMP redirects
    "net.ipv4.conf.all.accept_redirects" = 0;
    "net.ipv6.conf.all.accept_redirects" = 0;
    "net.ipv4.conf.default.accept_redirects" = 0;
    "net.ipv6.conf.default.accept_redirects" = 0;

    # Ignore ICMP redirects from non-GW hosts
    "net.ipv4.conf.all.secure_redirects" = 1;
    "net.ipv4.conf.default.secure_redirects" = 1;

    # Ignore source-routed packets
    "net.ipv4.conf.all.accept_source_route" = 0;
    "net.ipv4.conf.default.accept_source_route" = 0;
    "net.ipv6.conf.all.accept_source_route" = 0;
    "net.ipv6.conf.default.accept_source_route" = 0;

    # Ignore ICMP broadcasts to avoid participating in Smurf attacks
    "net.ipv4.icmp_echo_ignore_broadcasts" = 1;

    # Ignore bad ICMP errors
    "net.ipv4.icmp_ignore_bogus_error_responses" = 1;

    # Log spoofed, source-routed, and redirect packets
    "net.ipv4.conf.all.log_martians" = 1;
    "net.ipv4.conf.default.log_martians" = 1;

    # Randomize addresses of mmap base, heap, stack and VDSO page
    "kernel.randomize_va_space" = 2;

    # Provide protection from ToCToU races
    "fs.protected_hardlinks" = 1;
    "fs.protected_symlinks" = 1;

    # Make locating kernel addresses more difficult
    "kernel.kptr_restrict" = 1;
  };

  # Make unfree closed-source binary firmwares available to the kernel so that
  # they can be loaded to the devices that need them. This option only enables
  # firmwares with a license that allows them to be redistributed.
  hardware.enableRedistributableFirmware = true;
}
