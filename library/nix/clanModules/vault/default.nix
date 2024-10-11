{ self, config, lib, pkgs, ... }:
let
  inherit (config.networking) hostName;
  nixpkgs-unfree' = self.inputs.nixpkgs-unfree.legacyPackages.${pkgs.system};
  serverCfg = config.clan.clan-destiny.services.vault-server;
  clientCfg = config.clan.clan-destiny.services.vault-client;
  vars = config.clan.core.vars.generators.clan-destiny-vault;
  commonVars = config.clan.core.vars.generators.clan-destiny-vault-common;
in
{
  options.clan.clan-destiny.services.vault-server = {
    enable = lib.mkEnableOption "Configure and enable the vault-server";
  };
  options.clan.clan-destiny.services.vault-client = {
    enable = lib.mkEnableOption ''
      Setup the TLS CA certificate used by Vault along with the right
      environment vars.
    '';
  };
  config = lib.mkMerge [
    (lib.mkIf serverCfg.enable {
      clan.core.vars.generators.clan-destiny-vault = {
        files.tlsCertChain.owner = "vault";
        files.tlsKey.owner = "vault";
        prompts.tlsCertChain = {
          createFile = true;
          description = ''
            The TLS server certificate used by Vault followed by the CA
            certificate.
          '';
          type = "multiline";
        };
        prompts.tlsKey = {
          createFile = true;
          description = "The key for the TLS certificate used by Vault";
          type = "multiline";
        };
      };
      services.vault = {
        enable = true;
        tlsCertFile = vars.files.tlsCertChain.path;
        tlsKeyFile = vars.files.tlsKey.path;
        storageBackend = "file";
        storagePath = config.users.users.vault.home;
#   Note: the binaries built par Nix do not support the UI:
#
#   <h1>Vault UI is not available in this binary.</h1>
#   </div>
#   <p>To get Vault UI do one of the following:</p>
#   <ul>
#   <li><a href="https://www.vaultproject.io/downloads.html">Download an official release</a></li>
#   <li>Run <code>make bin</code> to create your own release binaries.
#   <li>Run <code>make dev-ui</code> to create a development binary with the UI.
#   </ul>
#
#   extraConfig = ''
#     ui = true
#     api_addr = "https://${vaultFQDN}"
#   '';
      };
    })
    (lib.mkIf clientCfg.enable {
      environment.variables = {
        VAULT_ADDR = config.services.vault.address;
        VAULT_CACERT = commonVars.files.tlsCaCert.path;
        VAULT_CLIENT_TIMEOUT = "3";
      };
      environment.systemPackages = [
        nixpkgs-unfree'.vault
      ];
      clan.core.vars.generators.clan-destiny-vault-common = {
        prompts.tlsCaCert = {
          createFile = true;
          description = "The TLS Certificate Authority certificate used by Vault";
          type = "multiline";
        };
        share = true;
      };
    })
  ];
}
