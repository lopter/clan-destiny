# Configure OpenSSH with mosh.
{ config, lib, ... }:
let
  cfg = config.clan-destiny.ssh;
in
{
  options.clan-destiny.ssh = with lib; {
    moshPortsRange = mkOption {
      type = types.attrsOf types.port;
      description = "The UDP port range to open for mosh";
      default = { from = 60000; to = 61000; };
    };
  };

  config = {
    services.openssh.enable = true;
    services.openssh.knownHosts =
    let
      cleanAttrs = (_: details: {
        inherit (details) hostNames;
        publicKey = details.sshPubKey;
      });
    in
      builtins.mapAttrs cleanAttrs config.clan-destiny.typed-tags.knownHosts;
    services.openssh.settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "yes";
    };
    networking.firewall.allowedUDPPortRanges = [ cfg.moshPortsRange ];
    programs.mosh.enable = true;
  };
}
