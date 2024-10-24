{ lib, ... }:
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
}
