{ lib, self, ... }:
{
  nix = {
    gc = {
      automatic = true;
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
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      auto-optimise-store = true;
    };
  };
}
