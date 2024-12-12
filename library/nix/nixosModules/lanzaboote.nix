{ config, lib, self, ... }:
let
  inherit (self.inputs) lanzaboote;

  enabled = config.boot.lanzaboote.enable;
in
{
  imports = [
    lanzaboote.nixosModules.lanzaboote
  ];

  config = lib.mkIf enabled {
    assertions = [{
      assertion = config.boot.swraid.enable == false;
      message = ''
        lanzaboote (secure boot) cannot be used on an MD array.
      '';
    }];

    boot = {
      bootspec.enable = true; # Enabled by default since RFC 125 was merged.
      # Next setting is also set to true by clan-core, note that it
      # cannot be used if booting off a RAID array managed with md.
      initrd.systemd.enable = true;
      # Generate pkiBundle with:
      #
      # sudo mkdir /etc/secureboot
      # sudo nix run 'nixpkgs#sbctl' create-keys
      lanzaboote.pkiBundle = "/etc/secureboot";
      loader.systemd-boot.enable = lib.mkForce false; # lanzaboote replaces it.
    };
  };
}
