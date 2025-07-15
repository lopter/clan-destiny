{ lib, self, ... }:
let
  lanInterfaces = [ "enp6s0" ];
in
{
  imports = [
    self.nixosModules.r8125
  ];

  nixpkgs.hostPlatform = lib.mkForce "x86_64-linux";

  clan-destiny.typed-tags.interfacesByRole = {
    lan = lanInterfaces;
  };
}
