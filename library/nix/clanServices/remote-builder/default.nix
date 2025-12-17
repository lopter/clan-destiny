{ lib, ... }:
let
  # Tu te demandes comment tu peux set une option commune à tous les roles ?
in
{
  _class = "clan-service";
  manifest.name = "clan-destiny/remote-builder";
  manifest.description = "Run Nix builds on machines in your network";
  manifest.categories = [ "Utility" ];

  roles.client = {
    perInstance = 
      { settings, machine, ... }:
      {
        nixosModule =
          { config, lib, ... }:
          {
            # client side need private key for each server from the client->server var
            # setup root ssh config for the server
          };
      };
  };
  
  roles.common = {
    interface.options = {
      # c'est un peu con de devoir créer l'user séparement,
      # il pouvoir recevoir usergroups
      usergroups = lib.mkOption {

      };
    };
  };

  roles.server = {
    perInstance = 
      { machine, roles, settings, ... }:
      let
        inherit (roles.common.machines.${machine.name}.settings) user;
      in
      {
        nixosModule =
          { config, lib, ... }:
          {
            nix.settings.trusted-users = [ user ];

            # server side need public key from each client from the client->server var
            users.users.${user} = {
              createHome = true;
              homeMode = "0500";
              openssh.authorizedKeys.keys = [
              ];
            };
          };
      };
  };
}
