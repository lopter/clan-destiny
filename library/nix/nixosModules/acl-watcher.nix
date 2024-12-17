{
  config,
  lib,
  pkgs,
  self,
  ...
}:
let
  inherit (config.nixpkgs.hostPlatform) system;
  destiny-core' = self.inputs.destiny-core.packages.${system};
  description = "Use watchman to enforce permissions, and ACLs, when files are copied to certain folders";
  cfg = config.clan-destiny.acl-watcher;
in
{
  options.clan-destiny.acl-watcher.enable = lib.mkEnableOption description;
  config.systemd.services."clan-destiny-acl-watcher-goinfre" = lib.mkIf cfg.enable {
    inherit description;
    wantedBy = [ "multi-user.target" ];
    path = [
      destiny-core'.acl-watcher
      pkgs.watchman
    ];
    serviceConfig = {
      ExecStart = "${destiny-core'.acl-watcher}/bin/acl-watcher --debug true goinfre";
      Restart = "always";
      RestartMaxDelaySec = 600;
      RestartSteps = 10;
    };
  };
}
