{ ... }:
{
  perSystem =
    { pkgs, ... }:
    {
      packages.syncthing-init-ignore-service = pkgs.writeShellApplication {
        name = "syncthing-init-ignore-service";
        text = builtins.readFile ./syncthing-init-ignore-service;
        runtimeInputs = [ pkgs.coreutils ];
      };
      packages.syncthing-init-remove-default-folder = pkgs.writeShellApplication {
        name = "syncthing-init-remove-default-folder";
        text = builtins.readFile ./syncthing-init-remove-default-folder;
        runtimeInputs = with pkgs; [ libxml2 curl ];
      };
    };
}
