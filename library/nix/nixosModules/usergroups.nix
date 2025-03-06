{ config, lib, pkgs, self, ... }:
let
  cfg = config.clan-destiny.usergroups;
  cfg' = self.inputs.destiny-config.lib.usergroups or { };
  vars = config.clan.core.vars.generators.clan-destiny-user-passwords;

  isNormalUser = userName: userCfg: userCfg.isNormalUser or false;
  normalUsers = lib.filterAttrs isNormalUser cfg'.users;
  userNames = builtins.attrNames normalUsers;
in
{
  # This is option is for use by our `destiny-config` input.
  options.clan-destiny.usergroups = {
    createNormalUsers = lib.mkEnableOption {
      description = ''
        Enable the creation of non-system users and groups defined in the
        destiny-config flake.
      '';
      default = false;
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

    (lib.mkIf cfg.createNormalUsers {
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
        files = builtins.listToAttrs (builtins.foldl' mkFiles [ ] userNames);
        prompts = builtins.listToAttrs (map mkPrompt userNames);
        runtimeInputs = with pkgs; [
          coreutils
          xkcdpass
          mkpasswd
        ];
        script = ''
          trim() {
            tr -d "\n"
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
        lib.genAttrs userNames setUserPassword;
    })
  ];
}
