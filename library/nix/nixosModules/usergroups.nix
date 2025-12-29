{ config, lib, pkgs, self, ... }:
let
  cfg = config.clan-destiny.usergroups;
  cfg' = self.inputs.destiny-config.lib.usergroups;
  vars = config.clan.core.vars.generators.clan-destiny-user-passwords;

  userNames = builtins.attrNames cfg'.familyUsers;
in
{
  # This option is for use by our `destiny-config` input.
  options.clan-destiny.usergroups = {
    createNormalUsers = lib.mkOption {
      type = with lib.types; listOf (enum userNames);
      description = ''
        Enable the creation of non-system users and groups defined in the
        destiny-config flake.

        Note: This will generate passwords for all users in the destiny-config
        flake but only set/use passwords in the NixOS config for the users
        specified with this option. We need to do this in order to keep the
        vars generator the same accross machines, see [#5253].

        [#5253]: https://git.clan.lol/clan/clan-core/issues/5253
      '';
      default = [ ];
    };
  };

  # "Normal" users and groups get created in `destiny-config`, and we set their
  # passwords here. I am not using the upstream `user-password` module: as of
  # 2025-02-22, it creates machine-specific password, while I want those
  # passwords to be the same across all machines.
  config = lib.mkMerge [
    {
      users.mutableUsers = false;
    }

    (lib.mkIf (builtins.length cfg.createNormalUsers > 0) {
      clan.core.vars.generators.clan-destiny-user-passwords =
      let
        mkFiles = acc: userName: acc ++ [
          (lib.nameValuePair "${userName}-password" { deploy = false; })
          (lib.nameValuePair "${userName}-password-hash" { neededFor = "users"; })
        ];
        mkPrompt = userName: {
          name = "${userName}-password";
          value.description = "The password for the user ${userName}";
          value.type = "hidden";
          value.persist = true;
        };
        mkScript = userName: ''
          if [ -z "$(trim < "$prompts/${userName}-password" | tee "$out/${userName}-password")" ]; then
            xkcdpass --numwords 4 --count 1 | trim > $out/${userName}-password
          fi
          mkpasswd -s -m sha-512 < $out/${userName}-password | trim > $out/${userName}-password-hash
        '';
      in
      {
        share = true;
        files = builtins.listToAttrs (builtins.foldl' mkFiles [ ] userNames);
        prompts = builtins.listToAttrs (map mkPrompt userNames);
        runtimeInputs = with pkgs; [
          coreutils
          gawk
          xkcdpass
          mkpasswd
        ];
        script = ''
          trim() {
            awk '{ gsub(/^[[:space:]]+|[[:space:]]+$/, ""); print }'
          }

          ${lib.concatLines (map mkScript userNames)}
        '';
      };

      users.users =
      let
        setUserPassword = userName: {
          hashedPasswordFile = vars.files."${userName}-password-hash".path;
        };
      in
        lib.genAttrs cfg.createNormalUsers setUserPassword;
    })
  ];
}
