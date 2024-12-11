{ self, config, lib, pkgs, ... }:
let
  inherit (config.networking) hostName;
  inherit (config.nixpkgs.hostPlatform) system;
  inherit (config.lib.clan-destiny) ports;
  vaultFQDN = self.inputs.destiny-config.lib.vault.fqdn;
  nixpkgs-unfree' = self.inputs.nixpkgs-unfree.legacyPackages.${system};
  vault = nixpkgs-unfree'.vault.overrideAttrs (prev: { doCheck = false; });
  destiny-core' = self.inputs.destiny-core.packages.${system};
  serverCfg = config.clan-destiny.vault-server;
  clientCfg = config.clan-destiny.vault-client;
  vars = config.clan.core.vars.generators.clan-destiny-vault;
  commonVars = config.clan.core.vars.generators.clan-destiny-vault-common;
in
{
  options.clan-destiny.vault-server = {
    enable = lib.mkEnableOption "Configure and enable the vault-server";
  };
  options.clan-destiny.vault-client = {
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
        package = vault;
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
      clan-destiny.nixpkgs.unfreePredicates = [ "vault" ];
      environment.variables = {
        VAULT_ADDR =
          if serverCfg.enable then
            # If you are using Tailscale and try to connect to the local vault
            # through its (local) Tailscale IP, the iptables rules set in
            # `ts-input` by Tailscale will prevent you to do that, since the
            # traffic will arrive on the loopback interface instead of the
            # tailscale interface. We avoid getting blocked by this firewall
            # rule by trying to connect on the loopback address instead:
            lib.info
              (
                "Using 127.0.0.1 instead of ${vaultFQDN} in VAULT_ADDR "
                + "since we seem to be on the vault server"
              )
              "https://127.0.0.1:${toString ports.vault}/"
          else
              config.lib.clan-destiny.vault.addr;
        VAULT_TLS_SERVER_NAME = vaultFQDN;
        VAULT_CACERT = commonVars.files.tlsCaCert.path;
        VAULT_CLIENT_TIMEOUT = "3";
      };
      environment.systemPackages = [
        destiny-core'.vault-shell
        vault
      ];
      systemd.tmpfiles.rules = [
        "r! %h/.vault-token - - - - -"
      ];
      clan.core.vars.generators.clan-destiny-vault-common = {
        files.tlsCaCert.secret = false;
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
