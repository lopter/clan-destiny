{
  lib,
  self,
  clan-core,
  ...
}:
let
  inherit (self.inputs) nixos-hardware;
in
{
  imports = [
    clan-core.clanModules.user-password

    nixos-hardware.nixosModules.lenovo-thinkpad-t480s

    self.nixosModules.home-kal
  ];

  nixpkgs.hostPlatform = lib.mkForce "x86_64-linux";

  boot.loader.efi.canTouchEfiVariables = true;
  # Secure boot using lanzaboote (replaces `boot.loader.systemd-boot`):
  boot.lanzaboote.enable = true;

  clan-destiny = {
    usergroups.createNormalUsers = true;
    vault-client.enable = true;
  };
  clan.user-password.user = "kal";

  services = {
    tailscale.enable = true;
    fwupd.enable = true;
  };

  networking.networkmanager.ensureProfiles.profiles = {
    "38C3" = {
      connection = {
        id = "38C3";
        type = "wifi";
      };
      wifi = {
        mode = "infrastructure";
        ssid = "38C3";
      };
      wifi-security = {
        auth-alg = "open";
        key-mgmt = "wpa-eap";
      };
      "802-1x" = {
        anonymous-identity = "38C3";
        eap = "ttls;";
        identity = "38C3";
        password = "38C3";
        phase2-auth = "pap";
        altsubject-matches = "DNS:radius.c3noc.net";
        ca-cert = "${builtins.fetchurl {
          url = "https://letsencrypt.org/certs/isrgrootx1.pem";
          sha256 = "sha256:1la36n2f31j9s03v847ig6ny9lr875q3g7smnq33dcsmf2i5gd92";
        }}";
      };
      ipv4 = {
        method = "auto";
      };
      ipv6 = {
        addr-gen-mode = "default";
        method = "auto";
      };
    };
  };
}
