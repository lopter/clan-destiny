{ pkgs, config, ... }:
{
  environment.systemPackages = with pkgs; [
    acl
    alacritty.terminfo
    attr
    bcc
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
  ] ++ lib.optional config.powerManagement.powertop.enable powertop;
}