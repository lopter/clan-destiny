{
  description = "No Man's Lab";

  inputs = {
    clan-core.url = "git+https://git.clan.lol/clan/clan-core";
  };

  outputs =
    { self, clan-core, ... }@inputs:
    let
      # Usage see: https://docs.clan.lol
      clan = clan-core.lib.buildClan {
        directory = self;
        # Ensure this is unique among all clans you want to use.
        meta.name = "ClanDestiny";

        # Prerequisite: boot into the installer.
        # See: https://docs.clan.lol/getting-started/installer
        # local> mkdir -p ./machines/machine1
        # local> Edit ./machines/<machine>/configuration.nix to your liking.
        machines = {
          # The name will be used as hostname by default.
          nsrv-sfo-ashpool = { };
        };
      };
    in
    {
      # All machines managed by Clan.
      inherit (clan) nixosConfigurations clanInternals;
      # Add the Clan cli tool to the dev shell.
      # Use "nix develop" to enter the dev shell.
      devShells =
        clan-core.inputs.nixpkgs.lib.genAttrs
          [
            "x86_64-linux"
            "aarch64-linux"
            "aarch64-darwin"
            "x86_64-darwin"
          ]
          (system: {
            default = clan-core.inputs.nixpkgs.legacyPackages.${system}.mkShell {
              packages = [ clan-core.packages.${system}.clan-cli ];
            };
          });
    };
}
