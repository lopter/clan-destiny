{ pkgs, ... }:
{
  # note: kmag does not work on wayland (kwin has a builtin zoom feature).
  # see: https://bugs.kde.org/show_bug.cgi?id=438912
  environment.systemPackages = with pkgs.kdePackages; [
    kcolorchooser
    kruler
  ];
  hardware.bluetooth.enable = true; # pull bluedevil & bluez-qt
  networking.networkmanager.enable = true; # pull plasma-pm
  services.pipewire.pulse.enable = true; # pull plasma-pa
  services.flatpak.enable = true;
  services.hardware.bolt.enable = true;
  services.printing.enable = true;
  services.displayManager.sddm.wayland.enable = true;
  services.displayManager.sddm.enable = true;
  services.desktopManager.plasma6.enable = true;
  fonts.enableDefaultPackages = true;
}
