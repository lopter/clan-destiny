{ lib, self, ... }:
{
  nix = {
    gc = {
      automatic = lib.mkDefault true;
      options = "--delete-older-than 31d";
      dates = "03:15";
    };
    nixPath = lib.mkForce [
      "nixpkgs=${self.inputs.nixpkgs}"
    ];
    registry = {
      nixpkgs.flake = self.inputs.nixpkgs;
    };
    settings = {
      allowed-users = [ "root" ];
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      auto-optimise-store = true;
    };
  };
}
