{
  self,
  config,
  options,
  lib,
  pkgs,
  system,
  ...
}:

let
  inherit (self.inputs.clan-core.inputs) sops-nix;

  cfg = config.sops;
  sopsManifestFor = pkgs.callPackage ./sops-manifest-for.nix {
    inherit cfg;
    inherit (pkgs) writeTextFile;
  };
  suffix = "";
  extraJson = { };
  manifest = sopsManifestFor suffix regularSecrets extraJson;

  pathNotInStore = lib.mkOptionType {
    name = "pathNotInStore";
    description = "path not in the Nix store";
    descriptionClass = "noun";
    check = x: !lib.path.hasStorePathPrefix (/. + x);
    merge = lib.mergeEqualOption;
  };

  regularSecrets = lib.filterAttrs (_: v: !v.neededForUsers) cfg.secrets;

  secretType = lib.types.submodule (
    { config, ... }:
    {
      config = {
        sopsFile = lib.mkOptionDefault cfg.defaultSopsFile;
        sopsFileHash = lib.mkOptionDefault (
          lib.optionalString cfg.validateSopsFiles "${builtins.hashFile "sha256" config.sopsFile}"
        );
      };
      options = {
        name = lib.mkOption {
          type = lib.types.str;
          default = config._module.args.name;
          description = ''
            Name of the file used in /run/secrets
          '';
        };
        key = lib.mkOption {
          type = lib.types.str;
          default = config._module.args.name;
          description = ''
            Key used to lookup in the sops file.
            No tested data structures are supported right now.
            This option is ignored if format is binary.
          '';
        };
        path = lib.mkOption {
          type = lib.types.str;
          default =
            if config.neededForUsers then
              "/run/secrets-for-users/${config.name}"
            else
              "/run/secrets/${config.name}";
          defaultText = "/run/secrets-for-users/$name when neededForUsers is set, /run/secrets/$name when otherwise.";
          description = ''
            Path where secrets are symlinked to.
            If the default is kept no symlink is created.
          '';
        };
        format = lib.mkOption {
          type = lib.types.enum [
            "yaml"
            "json"
            "binary"
            "dotenv"
            "ini"
          ];
          default = cfg.defaultSopsFormat;
          description = ''
            File format used to decrypt the sops secret.
            Binary files are written to the target file as is.
          '';
        };
        mode = lib.mkOption {
          type = lib.types.str;
          default = "0400";
          description = ''
            Permissions mode of the in octal.
          '';
        };
        owner = lib.mkOption {
          type = lib.types.str;
          default = "root";
          description = ''
            User of the file.
          '';
        };
        group = lib.mkOption {
          type = lib.types.str;
          default = "root";
          defaultText = lib.literalMD "{option}`config.users.users.\${owner}.group`";
          description = ''
            Group of the file.
          '';
        };
        sopsFile = lib.mkOption {
          type = lib.types.path;
          defaultText = "\${config.sops.defaultSopsFile}";
          description = ''
            Sops file the secret is loaded from.
          '';
        };
        sopsFileHash = lib.mkOption {
          type = lib.types.str;
          readOnly = true;
          description = ''
            Hash of the sops file, useful in <xref linkend="opt-systemd.services._name_.restartTriggers" />.
          '';
        };
        restartUnits = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          example = [ "sshd.service" ];
          description = ''
            Names of units that should be restarted when this secret changes.
            This works the same way as <xref linkend="opt-systemd.services._name_.restartTriggers" />.
          '';
        };
        reloadUnits = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          example = [ "sshd.service" ];
          description = ''
            Names of units that should be reloaded when this secret changes.
            This works the same way as <xref linkend="opt-systemd.services._name_.reloadTriggers" />.
          '';
        };
        neededForUsers = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = ''
            Enabling this option causes the secret to be decrypted before users and groups are created.
            This can be used to retrieve user's passwords from sops-nix.
            Setting this option moves the secret to /run/secrets-for-users and disallows setting owner and group to anything else than root.
          '';
        };
      };
    }
  );
in
{
  config.clan-destiny.fly-io-pop.secretsManifest = manifest;

  options.clan-destiny.fly-io-pop.secretsManifest = lib.mkOption {
    type = lib.types.package;
  };

  options.sops = {
    secrets = lib.mkOption {
      type = lib.types.attrsOf secretType;
      default = { };
      description = ''
        Path where the latest secrets are mounted to.
      '';
    };

    defaultSopsFile = lib.mkOption {
      type = lib.types.path;
      description = ''
        Default sops file used for all secrets.
      '';
    };

    defaultSopsFormat = lib.mkOption {
      type = lib.types.str;
      default = "yaml";
      description = ''
        Default sops format used for all secrets.
      '';
    };

    validateSopsFiles = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Check all sops files at evaluation time.
        This requires sops files to be added to the nix store.
      '';
    };

    keepGenerations = lib.mkOption {
      type = lib.types.ints.unsigned;
      default = 1;
      description = ''
        Number of secrets generations to keep. Setting this to 0 disables pruning.
      '';
    };

    log = lib.mkOption {
      type = lib.types.listOf (
        lib.types.enum [
          "keyImport"
          "secretChanges"
        ]
      );
      default = [
        "keyImport"
        "secretChanges"
      ];
      description = "What to log";
    };

    environment = lib.mkOption {
      type = lib.types.attrsOf (lib.types.either lib.types.str lib.types.path);
      default = { };
      description = ''
        Environment variables to set before calling sops-install-secrets.

        The values are placed in single quotes and not escaped any further to
        allow usage of command substitutions for more flexibility. To properly quote
        strings with quotes use lib.escapeShellArg.

        This will be evaluated twice when using secrets that use neededForUsers but
        in a subshell each time so the environment variables don't collide.
      '';
    };

    package = lib.mkOption {
      type = lib.types.package;
      default = sops-nix.packages.${system}.sops-install-secrets;
      description = ''
        sops-install-secrets package to use.
      '';
    };

    validationPackage = lib.mkOption {
      type = lib.types.package;
      default =
        if pkgs.stdenv.buildPlatform == pkgs.stdenv.hostPlatform then
          cfg.package
        else
          sops-nix.packages.${pkgs.stdenv.hostPlatform.system}.sops-install-secrets;
      defaultText = lib.literalExpression "config.sops.package";

      description = ''
        sops-install-secrets package to use when validating configuration.

        Defaults to sops.package if building natively, and a native version of sops-install-secrets if cross compiling.
      '';
    };

    useTmpfs = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Use tmpfs in place of ramfs for secrets storage.

        *WARNING*
        Enabling this option has the potential to write secrets to disk unencrypted if the tmpfs volume is written to swap. Do not use unless absolutely necessary.

        When using a swap file or device, consider enabling swap encryption by setting the `randomEncryption.enable` option

        ```
        swapDevices = [{
          device = "/dev/sdXY";
          randomEncryption.enable = true;
        }];
        ```
      '';
    };

    age = {
      keyFile = lib.mkOption {
        type = lib.types.nullOr pathNotInStore;
        default = null;
        example = "/var/lib/sops-nix/key.txt";
        description = ''
          Path to age key file used for sops decryption.
        '';
      };

      generateKey = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Whether or not to generate the age key. If this
          option is set to false, the key must already be
          present at the specified location.
        '';
      };

      sshKeyPaths = lib.mkOption {
        type = lib.types.listOf lib.types.path;
        default = [ ];
        defaultText = lib.literalMD "The ed25519 keys from {option}`config.services.openssh.hostKeys`";
        description = ''
          Paths to ssh keys added as age keys during sops description.
        '';
      };
    };

    gnupg = {
      home = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "/root/.gnupg";
        description = ''
          Path to gnupg database directory containing the key for decrypting the sops file.
        '';
      };

      sshKeyPaths = lib.mkOption {
        type = lib.types.listOf lib.types.path;
        default = [ ];
        defaultText = lib.literalMD "The rsa keys from {option}`config.services.openssh.hostKeys`";
        description = ''
          Path to ssh keys added as GPG keys during sops description.
          This option must be explicitly unset if <literal>config.sops.gnupg.home</literal> is set.
        '';
      };
    };
  };
  imports = [
    (lib.mkRenamedOptionModule [ "sops" "gnupgHome" ] [ "sops" "gnupg" "home" ])
    (lib.mkRenamedOptionModule [ "sops" "sshKeyPaths" ] [ "sops" "gnupg" "sshKeyPaths" ])
  ];
}
