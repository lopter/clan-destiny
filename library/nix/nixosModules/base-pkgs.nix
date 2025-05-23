{ pkgs, config, ... }:
{
  environment.systemPackages =
    with pkgs;
    [
      acl
      alacritty.terminfo
      attr
      bcc
      bpftrace
      bridge-utils
      btop
      curl
      e2fsprogs # chattr
      fd
      file
      findutils # xargs
      git
      gptfdisk
      htop
      iftop
      inetutils
      iptables
      jq
      libcap_ng
      lsof
      mosh
      mtr
      neovim
      netcat-openbsd
      openssh
      openssl
      pciutils
      psmisc
      python3
      ripgrep
      rsync
      strace
      sysstat
      tcpdump
      tmux
      tree
      usbutils
    ]
    ++ lib.optional config.powerManagement.powertop.enable powertop;
}
