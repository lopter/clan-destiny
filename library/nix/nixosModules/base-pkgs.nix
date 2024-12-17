{ pkgs, config, ... }:
{
  environment.systemPackages =
    with pkgs;
    [
      acl
      alacritty.terminfo
      attr
      bcc
      bridge-utils
      btop
      curl
      fd
      file
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
