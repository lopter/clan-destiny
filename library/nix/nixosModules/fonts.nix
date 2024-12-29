{ pkgs, ... }:
{
  fonts.packages = with pkgs; [
    inconsolata
    nerd-fonts.bitstream-vera-sans-mono
    nerd-fonts.fira-mono
    nerd-fonts.inconsolata
    nerd-fonts.monofur
  ];
}
