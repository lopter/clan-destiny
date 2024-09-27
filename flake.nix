{
  description = "No Man's Lab";

  inputs = {
    catppuccin.url = "github:catppuccin/nix";

    # clan-core.url = "git+https://git.clan.lol/clan/clan-core";
    clan-core.url = "git+file:///stash/home/kal/cu/src/nix/clan-core?rev=86cb4035f4b834037a482b481f4d465032675ec2";
    clan-core.inputs.nixpkgs.follows = "nixpkgs";

    home-manager.url = "github:lopter/home-manager/kwriteconfig6";
    # home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    multilab.url = "git+ssh://gitolite.kalessin.fr/louis/multilab?ref=wip";

    multilab-config.url = "git+ssh://gitolite.kalessin.fr/louis/multilab-config?ref=main";
    multilab-config.inputs.nixpkgs.follows = "nixpkgs";
    multilab-config.inputs.multilab.follows = "multilab";

    nixpkgs.follows = "multilab/nixpkgs";

    nixos-hardware.url = "github:NixOS/nixos-hardware";

    plasma-manager = {
      url = "github:nix-community/plasma-manager";
      inputs.nixpkgs.follows = "multilab/nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };

  };

  outputs =
    { self, clan-core, multilab, multilab-config, ... }@inputs:
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
          lady-3jane = { };
        };
      };

      devShell = system: {
        packages = [
          clan-core.packages.${system}.clan-cli
        ] ++ (with multilab.packages.${system}; [
          git-fetch-and-checkout
          n
        ]);

        shellHook = ''
          export SOPS_PGP_FP=ADB6276965590A096004F6D1E114CBAE8FA29165
        '';
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
            # "aarch64-linux"
            # "aarch64-darwin"
            # "x86_64-darwin"
          ]
          (system: {
            default = clan-core.inputs.nixpkgs.legacyPackages.${system}.mkShell (devShell system);
          });
      lib.clan = clan;
    };
}
