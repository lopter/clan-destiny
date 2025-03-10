{ pkgs, ... }:
{
  clan-destiny.nixpkgs.unfreePredicates = [
    "corefonts"
    "vista-fonts"
  ];

  fonts.packages = with pkgs; [
    corefonts
    inconsolata
    nerd-fonts.bitstream-vera-sans-mono
    nerd-fonts.fira-mono
    nerd-fonts.inconsolata
    nerd-fonts.monofur
    vistafonts
  ];
}
