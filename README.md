# No man's lab

This [Nix flake] holds [NixOS] and [Clan] configurations for my "homelab": self-hosted services for me and the friendmily.

[Clan] is a framework to manage multiple NixOS machines, secrets, users, and mesh networking. This repository is currently setup with one user, and [Tailscale] for networking[^clan-networking]. Join us on Matrix at [#clan:lassul.us](https://matrix.to/#/#clan:lassul.us).

[Nix flake]: https://wiki.nixos.org/wiki/Flakes
[NixOS]: https://nixos.org/
[Clan]: https://clan.lol/
[Tailscale]: https://tailscale.com/
[ZeroTier]: https://www.zerotier.com/
[^clan-networking]: Clan uses [ZeroTier] by default as of December 2024.

With Clan, a single or small group of operators can provide durable infrastructure for small to medium organizations, with maybe less hair loss than previous attempts. I wish I can eventually setup something like [kanidm] + [libkrimes] for an user directory, proper SSO, and portable file sharing that works everywhere (aka [SMB] see [kanidm:discussion#2755]).

[kanidm]: https://github.com/kanidm/kanidm
[libkrimes]: https://github.com/kanidm/libkrimes
[SMB]: https://en.wikipedia.org/wiki/Server_Message_Block
[kanidm:discussion#2755]: https://github.com/kanidm/kanidm/discussions/2755

# See also

This depends on two other repositories I own:

- [destiny-core]: contains potentially reusable code that I authored and anyone could depend on;
- `destiny-config`: contains private configuration files.

[destiny-core]: https://github.com/lopter/destiny-core
