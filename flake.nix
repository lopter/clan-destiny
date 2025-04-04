{
  description = "No Man's Lab";

  inputs = {
    catppuccin.url = "github:catppuccin/nix";
    catppuccin.inputs.nixpkgs.follows = "nixpkgs";

    clan-core.follows = "destiny-core/clan-core";
    clan-core.inputs.nixpkgs.follows = "nixpkgs";

    destiny-core.url = "git+ssh://gitolite@gitolite.kalessin.fr/destiny-core?ref=main";
    # destiny-core.url = "git+file:///stash/home/kal/cu/projs/destiny-core";

    destiny-config.url = "git+ssh://gitolite@gitolite.kalessin.fr/louis/destiny-config?ref=main";
    # destiny-config.url = "git+file:///stash/home/kal/cu/projs/destiny-config";
    destiny-config.inputs.nixpkgs.follows = "nixpkgs";
    destiny-config.inputs.destiny-core.follows = "destiny-core";

    flake-parts.url = "github:hercules-ci/flake-parts";
    flake-parts.inputs.nixpkgs-lib.follows = "nixpkgs";

    # home-manager.url = "github:lopter/home-manager/kwriteconfig6";
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    lanzaboote.url = "github:nix-community/lanzaboote";
    lanzaboote.inputs.nixpkgs.follows = "nixpkgs";

    nix2container.follows = "destiny-core/nix2container";
    nix2container.inputs.nixpkgs.follows = "nixpkgs";

    nixpkgs.follows = "destiny-core/nixpkgs";
    nixpkgs-unfree.follows = "destiny-core/nixpkgs-unfree";
    nixpkgs-unfree.inputs.nixpkgs.follows = "nixpkgs";

    nixos-hardware.url = "github:lopter/nixos-hardware?ref=lo-aoostar-r1-n100";

    plasma-manager = {
      url = "github:nix-community/plasma-manager";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };
  };

  outputs =
    inputs@{
      self,
      flake-parts,
      destiny-config,
      ...
    }:
    flake-parts.lib.mkFlake { inherit inputs; } (
      { lib, withSystem, ... }:
      {
        systems = [
          "x86_64-linux"
          "aarch64-linux"
          "x86_64-darwin"
          "aarch64-darwin"
        ];
        imports = [
          inputs.clan-core.flakeModules.default

          ./library/nix/flake-module.nix
          ./library/nix/nixosModules/flake-module.nix
          ./library/nix/packages/fly-io-pop/flake-module.nix
        ];
        # https://docs.clan.lol/getting-started/flake-parts/
        clan = {
          inherit self;

          meta.name = "ClanDestiny";

          # Make flake available in modules
          specialArgs.self = {
            inherit (self)
              inputs
              lib
              nixosModules
              packages
              ;
          };
          # inventory.services = { };

          machines =
            let
              names = [
                "lady-3jane"
                "nsrv-sfo-ashpool"
                "nsrv-cdg-jellicent"
                "nsrv-cfr-scylla"
                "rpi-cdg-hass"
              ];
              mkMachine =
                hostname:
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
                  privateConfigModules = lib.optionals (builtins.hasAttr "nixosModules" destiny-config) (
                    builtins.attrValues destiny-config.nixosModules
                  );
                in
                {
                  imports =
                    hostConfigModules
                    ++ privateConfigModules
                    ++ [
                      self.nixosModules.shared
                    ];
                  networking.hostName = hostname;
                };
            in
            lib.genAttrs names mkMachine;
        };

        # Generate some custom installer for us outside of the clan logic,
        # this is useful for rescue, and disaster recovery operations:
        flake.nixosConfigurations.nixos-installer-x86_64-linux = withSystem "x86_64-linux" (
          { inputs', ... }:
          let
            emptyModule = { };
            attrPath = [
              "nixosModules"
              "knownSshKeys"
            ];
            maybeKnownSshKeysModule = lib.attrByPath attrPath emptyModule destiny-config;
            installerModule =
              {
                config,
                lib,
                pkgs,
                ...
              }:
              let
                destiny-core' = inputs'.destiny-core.packages;
                rootSshAuthorizedKeys = config.users.users.root.openssh.authorizedKeys.keys;
              in
              {
                environment.systemPackages = with pkgs; [
                  gnupg
                  pinentry-curses
                  pass

                  destiny-core'.chroot-enter
                  destiny-core'.mount-mnt
                ];
                networking.hostName = "clan-destiny-rescue";
                systemd.services.sshd.wantedBy = pkgs.lib.mkForce [ "multi-user.target" ];
                time.timeZone = "UTC";
                warnings = lib.optional (builtins.length rootSshAuthorizedKeys == 0) (
                  "No SSH key was configured for `root`, please set one "
                  + "if you want to remotely access the installer."
                );
              };
          in
          lib.nixosSystem {
            system = "x86_64-linux";
            specialArgs = {
              inherit
                inputs
                inputs'
                self
                lib
                ;
            };
            modules = [
              "${inputs.nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"

              installerModule
              maybeKnownSshKeysModule

              self.nixosModules.base-pkgs
              self.nixosModules.linux
              self.nixosModules.nix-settings
              self.nixosModules.ssh
              self.nixosModules.typed-tags
            ];
          }
        );

        perSystem =
          { pkgs, inputs', system, ... }:
          {
            packages.nginxWithPamSupport =
            let
              modulesArgsOverride = nginxMainline: nginxMainline.override(prev: {
                modules = with pkgs.nginxModules; [ brotli dav moreheaders pam ];
                withDebug = true;
              });
              setBuildFlagsAttrsOverride = nginxMainline: nginxMainline.overrideAttrs(prev: {
                CFLAGS = lib.concatStringsSep " " [
                  "-O3"
                  "-pipe"
                  "-fno-plt"
                  "-fexceptions"
                  "-Wp,-D_FORTIFY_SOURCE=3"
                  "-Wall"
                  "-Wextra"
                  "-Wstrict-prototypes"
                  "-Werror=format-security"
                  "-fstack-clash-protection"
                  "-fcf-protection"
                  "-fno-omit-frame-pointer"
                  "-mno-omit-leaf-frame-pointer"
                ];
              });
            in
              lib.pipe pkgs.nginxMainline [
                modulesArgsOverride
                setBuildFlagsAttrsOverride
              ];

            devShells.default = pkgs.mkShell {
              packages =
                (with inputs'.clan-core.packages; [
                  clan-cli
                ])
                ++ (with inputs'.destiny-core.packages; [
                  git-fetch-and-checkout
                  toolbelt
                  n
                ])
                ++ (with pkgs; [
                  age
                  flyctl
                  skopeo
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
                    runtimeInputs = [
                      fd
                      entr
                    ];
                  })

                  (writeShellScriptBin "build-live-cd" ''
                    ${lib.getExe nix} build .#nixosConfigurations.nixos-installer-x86_64-linux.config.system.build.isoImage "$@"
                  '')

                  (writeShellScriptBin "fly-pop" ''
                    if [ ! -f config/fly.toml ]; then
                      echo >&2 "config/fly.toml not found, make sure you are at the repo's root."
                      exit 1
                    fi
                    exec fly -c config/fly.toml -a clan-destiny-pop "$@"
                  '')

                  (writeShellScriptBin "pop-deploy" ''
                    set -e
                    if [ $# -eq 1 ] ; then
                      IMAGE_REPO="$1"
                      printf -- "--> Redeploying image %s\n" "$IMAGE_REPO"
                    else
                      IMAGE_TAG="$(nix eval --raw '.#packages.${system}.fly-io-pop.imageTag')"
                      IMAGE_REPO="registry.fly.io/clan-destiny-pop:$IMAGE_TAG"
                      nix run -L '.#fly-io-pop.copyToRegistry'
                    fi
                    exec fly-pop deploy --image "$IMAGE_REPO"
                  '')

                  (writeShellScriptBin "pop-releases" ''
                    exec fly-pop releases --image
                  '')

                  (writeShellScriptBin "pop-console" ''
                    set -e
                    if [ $# -eq 1 ] ; then
                      MACHINE_ID="$1"
                    else
                      machines="$(fly-pop machines list -j | jq -r '.[]["id"]')"
                      printf -- "--> Found %d machines:\n%s\n" "$(echo "$machines" | wc -l)" "$machines"
                      MACHINE_ID="$(echo "$machines" | shuf -n 1)"
                    fi
                    printf -- "--> Connecting to %s…\n" "$MACHINE_ID"
                    exec fly-pop console --machine "$MACHINE_ID"
                  '')

                  (writeShellScriptBin "pop-sops" ''
                    set -e
                    if [ ! -f config/fly.toml ]; then
                      echo >&2 "config/fly.toml not found, make sure you are at the repo's root."
                      exit 1
                    fi
                    sops_config="$(mktemp sops-XXXXXXXXXX.yaml)"
                    cleanup() {
                      rm -rf "$sops_config"
                    }
                    trap cleanup EXIT INT QUIT TERM
                    cat >"$sops_config" <<EOF
                    creation_rules:
                      - key_groups:
                        - pgp:
                          - $SOPS_PGP_FP
                        - age:
                          - age1zps7k9czhty4leyjfph8z3fd3lrl9j08aw0z7xctmp2jys2gdcesvnh7lx
                          - age105x37pue8hlm33dkmml946l4f74x6dpeq0yh38pw7zjc2gvsy5gspaykya
                    EOF
                    secrets_file=library/nix/packages/fly-io-pop/secrets.yaml
                    operation="$1"
                    set +e
                    set -x
                    if [[ "$operation" = "decrypt" || "$operation" = "rotate" ]]; then
                      sops "$@" "$secrets_file"
                    else
                      sops --config "$sops_config" "$@" "$secrets_file"
                    fi
                    rv=$?
                    set +x
                    exit $rv
                  '')
                ]);

              shellHook = ''
                export SOPS_PGP_FP=587982779FC79ED146018F8C4E65D33603D146A6
              '';
            };
          };
      }
    );
}
