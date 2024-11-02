{
  description = "No Man's Lab";

  inputs = {
    catppuccin.url = "github:catppuccin/nix";

    # clan-core.url = "git+https://git.clan.lol/clan/clan-core";
    clan-core.url = "git+file:///stash/home/kal/cu/src/nix/clan-core?rev=86cb4035f4b834037a482b481f4d465032675ec2";
    clan-core.inputs.nixpkgs.follows = "nixpkgs";

    flake-parts.url = "github:hercules-ci/flake-parts";
    flake-parts.inputs.nixpkgs-lib.follows = "nixpkgs";

    home-manager.url = "github:lopter/home-manager/kwriteconfig6";
    # home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    destiny-core.url = "git+ssh://gitolite.kalessin.fr/louis/destiny-core?ref=main";

    destiny-config.url = "git+ssh://gitolite.kalessin.fr/louis/destiny-config?ref=main";
    destiny-config.inputs.nixpkgs.follows = "nixpkgs";
    destiny-config.inputs.destiny-core.follows = "destiny-core";

    nix2container.url = "github:nlewo/nix2container";
    nix2container.inputs.nixpkgs.follows = "nixpkgs";

    nixpkgs.follows = "destiny-core/nixpkgs";
    nixpkgs-unfree.follows = "destiny-core/nixpkgs-unfree";
    nixpkgs-unfree.inputs.nixpkgs.follows = "nixpkgs";

    nixos-hardware.url = "github:NixOS/nixos-hardware";

    plasma-manager = {
      url = "github:nix-community/plasma-manager";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };
  };

  outputs =
    inputs@{
      self,
      clan-core,
      flake-parts,
      destiny-config,
      ...
    }:
    flake-parts.lib.mkFlake { inherit inputs; } (
      { lib, ... }:
      {
        systems = [
          "x86_64-linux"
          "aarch64-linux"
          "x86_64-darwin"
          "aarch64-darwin"
        ];
        imports = [
          inputs.clan-core.flakeModules.default

          ./library/nix/clanModules/flake-module.nix
          ./library/nix/nixosModules/flake-module.nix
          ./library/nix/packages/fly-io-pop/flake-module.nix
        ];
        # https://docs.clan.lol/getting-started/flake-parts/
        clan = {
          meta.name = "ClanDestiny";

          # Make flake available in modules
          specialArgs.self = {
            inherit (self) clanModules inputs nixosModules packages;
          };
          directory = self;

          # inventory.services = { };

          machines =
          let
            names = [
              "nsrv-sfo-ashpool"
              "lady-3jane"
            ];
            mkMachine = hostname:
            let
              # We need to resolve those imports ahead of module evaluation,
              # because using the config (via `config.networking.hostName`)
              # while modules are being collected for evaluation will cause an
              # infinite recursion:
              hostConfigModules = builtins.filter builtins.pathExists [
                (./machines + "/${hostname}/configuration.nix")
                (./machines + "/${hostname}/disko.nix")
                (./machines + "/${hostname}/hardware-configuration.nix")
                ((builtins.toPath destiny-config) + "/machines/${hostname}/configuration.nix")
              ];
              privateConfigModules = lib.optionals
                (builtins.hasAttr "nixosModules" destiny-config)
                (builtins.attrValues destiny-config.nixosModules);
            in
              { lib, ... }:
              {
                imports = hostConfigModules ++ privateConfigModules ++ [
                  self.nixosModules.shared
                ];
                networking.hostName = hostname;
              };
          in
            lib.genAttrs names mkMachine;
        };
        perSystem =
          { lib, pkgs, inputs', ... }:
          {
            devShells.default = pkgs.mkShell {
              packages = (with inputs'.clan-core.packages; [
                clan-cli
              ]) ++ (with inputs'.destiny-core.packages; [
                git-fetch-and-checkout
                n
              ]) ++ (with pkgs; [
                age
                flyctl
                sops
                ssh-to-age
                python3Packages.ipython

                fd
                entr

                (writeShellApplication {
                  name = "watchloop-build-host";
                  text = ''
                    [ -n "$1" ] || {
                      printf "Usage: %s hostname\n" "$0"
                      exit 1;
                    }
                    printf "→ Press space to start a build manually and q to exit\n"
                    fd '.+\.(nix|py)$' | entr -p nix build --show-trace ".#nixosConfigurations.$1.config.system.build.toplevel" "$@"
                  '';
                  runtimeInputs = [ fd entr ];
                })

                (writeShellScriptBin "deploy-pop" ''
                  set -ex
                  nix run -L '.#fly-io-pop.copyToRegistry'
                  [ -f config/fly.toml ] && {
                    fly deploy -c config/fly.toml -i registry.fly.io/clan-destiny-pop:latest;
                  } || {
                    echo >&2 "config/fly.toml not found, make sure you are at the repo's root.";
                    exit 1;
                  }
                '')
              ]);

              shellHook = ''
                export SOPS_PGP_FP=ADB6276965590A096004F6D1E114CBAE8FA29165
              '';
            };
          };

        flake.lib = {
          # How could you actually make this a vars?
          zoneFromHostname = hostname:
          let
            knownZones = [ "sfo" ];
            capturePattern = builtins.concatStringSep "|" knownZones;
            groups = builtins.match ".+(${capturePattern})(-.+)?$" hostname;
          in
            if groups == null then null else builtins.elemAt groups 0;
        };
      }
    );
}
