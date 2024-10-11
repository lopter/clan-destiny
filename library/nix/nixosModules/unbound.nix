{ config, ... }:
{
  services.unbound = {
    settings.server = {
      num-threads = 1;
      so-reuseport = "yes";
      prefetch = "yes";
      harden-short-bufsize = "yes";
      harden-large-queries = "yes";
      harden-dnssec-stripped = "yes";
      msg-cache-size = "8m";
      msg-cache-slabs = 4;
      rrset-cache-size = "16m";
      rrset-cache-slabs = 4;
      infra-cache-skabs = 4;
      harden-glue = "yes";
      private-address = [
        "10.0.0.0/8"
        "100.64.0.0/10"
        "127.0.0.0/8"
        "169.254.0.0/16"
        "172.16.0.0/12"
        "192.168.0.0/16"
        "::1/128"
        "fc00::/7" # Unique Local Addresses (private ipv6 networks)
        "fe80::/10" # Link Local Addresses (link-local/stateless address autoconfiguration)
      ];
    };
  };
}
