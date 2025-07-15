{ config, lib, pkgs, self, ... }:
let
  cfg = config.clan-destiny.usergroups;
  cfg' = self.inputs.destiny-config.lib.usergroups;
  vars = config.clan.core.vars.generators.clan-destiny-user-passwords;
in
{
  # This is option is for use by our `destiny-config` input.
  options.clan-destiny.usergroups = {
    createNormalUsers = lib.mkOption {
      type = with lib.types; listOf (enum (builtins.attrNames cfg'.familyUsers));
      description = ''
        Enable the creation of non-system users and groups defined in the
        destiny-config flake.
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
        };
        mkScript = userName: ''
          if [ -n "$(cat $prompts/${userName}-password)" ]; then
            trim < $prompts/${userName}-password > $out/${userName}-password
          else
            xkcdpass --numwords 3 --delimiter - --count 1 | trim > $out/${userName}-password
          fi
          mkpasswd -s -m sha-512 < $prompts/${userName}-password | trim > $out/${userName}-password-hash
        '';
      in
      {
        share = true;
        files = builtins.listToAttrs (builtins.foldl' mkFiles [ ] cfg.createNormalUsers);
        prompts = builtins.listToAttrs (map mkPrompt cfg.createNormalUsers);
        runtimeInputs = with pkgs; [
          coreutils
          xkcdpass
          mkpasswd
        ];
        script = ''
          trim() {
            tr -d "\n"
          }

          ${lib.concatLines (map mkScript cfg.createNormalUsers)}
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
