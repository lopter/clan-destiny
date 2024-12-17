{ ... }:
{
  flake.clanModules = {
    backups = ./backups;
    certbot-vault = ./certbot-vault;
    nginx = ./nginx;
    postfix-relay = ./postfix-relay;
    vault = ./vault;
  };
}
