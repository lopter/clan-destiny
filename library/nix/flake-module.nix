{ lib, ... }:
{
  flake.lib.zoneFromHostname = import ./zoneFromHostname.nix;
  # Get the partition of the given number for the given storage device. Expand
  # to the correct path whether devices are addressed using /dev/disk/by- or
  # using something of the like of /dev/sda:
  flake.lib.diskPart =
    number: diskName:
    if builtins.isList (builtins.match ".+by-(id|uuid).+" diskName) then
      "${diskName}-part${toString number}"
    else
      "${diskName}${toString number}";
  flake.lib.diskById = id: "/dev/disk/by-id/${id}";
}
