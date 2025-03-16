{
  config,
  lib,
  pkgs,
  self,
  ...
}:
let
  inherit (self.inputs)
    catppuccin
    clan-core
    destiny-core
    destiny-config
    plasma-manager
    ;
  inherit (destiny-core.lib) attrsToEnvironmentString;
  inherit (config.lib.clan-destiny) ports usergroups;
  inherit (pkgs.stdenv.hostPlatform) system;

  user = "kal";
  userAuthorizedSSHKey = config.clan-destiny.typed-tags.knownSshKeys.louisGPGAuthKey;
  nixpkgsCfg = config.nixpkgs.config;
in
{
  imports = [
    catppuccin.nixosModules.catppuccin

    self.nixosModules.kde
    self.nixosModules.fonts
  ];

  home-manager.sharedModules = [
    catppuccin.homeManagerModules.catppuccin
    plasma-manager.homeManagerModules.plasma-manager
  ];

  home-manager.users."${user}" =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      vim-desert256 = pkgs.vimUtils.buildVimPlugin {
        pname = "vim-desert256";
        version = "2010-10-17";
        src = pkgs.fetchFromGitHub {
          owner = "vim-scripts";
          repo = "desert256.vim";
          rev = "28218ba05f77003e720ede1e74efaa17cc3e9051";
          hash = "sha256-QDen762FPk+ODrzpLZbGBFZoolk7UFSPxkjzy0EvrcU=";
        };
      };
      vim-lucius = pkgs.vimUtils.buildVimPlugin {
        pname = "vim-lucius";
        version = "2020-06-18";
        src = pkgs.fetchFromGitHub {
          owner = "jonathanfilip";
          repo = "vim-lucius";
          rev = "b5dea9864ae64714da4635993ad2fc2703e7c832";
          hash = "sha256-FlSqTEQyYm17vR7sNw5hlq2Hpz1cWYr23ARsVNibUBM=";
        };
      };
    in
    {
      # nix.extraConfig = ''
      #   experimental-features = nix-command flakes
      #   build-users-group = nixbld
      #   trusted-public-keys = devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw=
      #   extra-substituters = https://devenv.cachix.org
      # '';

      catppuccin.flavor = "latte";
      catppuccin.enable = true;

      home.homeDirectory = "/stash/home/${user}/cu";

      home.packages =
        with pkgs;
        [
          aspell
          aspellDicts.en
          aspellDicts.fr
          binutils
          direnv
          easytag
          entr
          # discord
          # fzf
          gnucash
          grim
          gv # replace with nix-visualize
          httpie
          hunspell
          hunspellDicts.en-us
          hunspellDicts.fr-any
          imagemagick
          inkscape
          ipcalc
          kdePackages.krdc
          lazygit
          libreoffice-qt
          man-pages
          man-pages-posix
          mercurial
          minicom
          mindforger
          # Until @teto merges the correct stuff:
          # See https://discourse.nixos.org/t/plugins-for-neovim-are-not-installed-for-neovim-qt/29712/10
          (neovim-qt.override { neovim = config.programs.neovim.finalPackage; })
          ncmpcpp
          nixd
          nix-output-monitor
          nix-prefetch-github
          nix-tree
          okteta
          (pass.override { waylandSupport = true; })
          picard
          pngcrush
          pv
          pwgen
          (python3.withPackages (
            ps: with ps; [
              ipython
              requests
              pyyaml
            ]
          ))
          qalculate-qt
          shellcheck
          signal-desktop
          slurp
          telegram-desktop
          tidal-hifi
          tig
          tldr
          ungoogled-chromium
          universal-ctags
          unoconv
          (vault.overrideAttrs (_prev: {
            doCheck = false;
          }))
          wl-clipboard
          xkcdpass
          yt-dlp
          zeal
          zotero
        ]
        ++ (with plasma-manager.packages.${system}; [
          rc2nix
        ])
        ++ (with clan-core.packages.${system}; [
            clan-cli
        ]);

      nixpkgs.config = nixpkgsCfg;

      programs.alacritty = {
        enable = false;
        settings = {
          mouse.hide_when_typing = true;
          font = {
            size = 12;
            normal = {
              family = "Inconsolata";
              style = "Regular";
            };
            bold = {
              family = "Inconsolata";
              style = "Bold";
            };
          };
          colors = lib.mkIf false {
            # let catppuccin control it
            draw_bold_text_with_bright_colors = true;
            primary = {
              background = "#000000";
              foreground = "#ffffff";
            };
            normal = {
              black = "#000000";
              red = "#9f4343";
              green = "#00aa00";
              yellow = "#aa5500";
              blue = "#2828e5";
              magenta = "#a742a7";
              cyan = "#60aaaa";
              white = "#ffffff";
            };
            bright = {
              black = "#555555";
              red = "#ff5555";
              green = "#55ff55";
              yellow = "#ffff55";
              blue = "#6464e5";
              magenta = "#a768a7";
              cyan = "#55ffff";
              white = "#a7a7a7";
            };
          };
          keyboard.bindings = [
            # Add support for Shift+Enter & Shift+Control,
            # if you wanna bind that in Vim someday:
            # {
            #   mods = "Shift";
            #   key = "Return";
            #   chars = "\\x1b[13;2u";
            # }
            # {
            #   mods = "Control";
            #   key = "Return";
            #   chars = "\\x1b[13;5u";
            # }
          ];
        };
      };

      programs.kitty = {
        enable = false;
        font.name = "Inconsolata";
        font.size = 12;
        settings = {
          #       color0  = "#000000"; # black
          #       color1  = "#9f4343"; # red
          #       color2  = "#00aa00"; # green
          #       color3  = "#aa5500"; # yellow
          #       color4  = "#2828e5"; # blue
          #       color5  = "#a742a7"; # magenta
          #       color6  = "#60aaaa"; # cyan
          #       color7  = "#ffffff"; # white
          #       color8  = "#555555"; # bright black
          #       color9  = "#ff5555"; # bright red
          #       color10 = "#55ff55"; # bright green
          #       color11 = "#ffff55"; # bright yellow
          #       color12 = "#6464e5"; # bright blue
          #       color13 = "#a768a7"; # bright magenta
          #       color14 = "#55ffff"; # bright cyan
          #       color15 = "#a7a7a7"; # bright white
          #       foreground = "#000000";
          #       background = "#ffffff";
          scrollback_lines = 10000;
          wheel_scroll_min_lines = 1;
          window_padding_width = 4;
          confirm_os_window_close = 0;
          show_hyperlink_targets = true;
          enable_audio_bell = false;
          copy_on_select = true;
          cursor_shape = "block";
          cursor_blink_interval = 0;
        };
      };

      programs.konsole = {
        enable = true;
        defaultProfile = "Catppuccin";
        profiles.Catppuccin = {
          font.name = "Inconsolata";
          font.size = 12;
          colorScheme = "Catppuccin-Late";
        };
      };

      programs.direnv = {
        enable = true;
      };

      # TODO: configure bash to be usable interactively: shared env with zsh.
      programs.bash = {
        enable = false;
      };

      programs.btop.enable = true;

      programs.fzf = {
        enable = true;
        defaultCommand = "rg --files --follow 2>&-";
        enableZshIntegration = true;
        enableBashIntegration = true;
      };

      programs.firefox = {
        enable = true;
        profiles =
          let
            mkContainer =
              attrs:
              {

              }
              // attrs;
          in
          {
            "s2nt6rj0.main" = {
              id = 0;
              isDefault = true;
              containers.banking = mkContainer {
                id = 1;
                icon = "dollar";
                color = "green";
              };
              containers.main = mkContainer {
                id = 2;
                icon = "circle";
                color = "blue";
              };
              containers.social = mkContainer {
                id = 3;
                icon = "briefcase";
                color = "pink";
              };
              containersForce = true;
              search.default = "Kagi";
              search.engines =
              let
                searchMusicBrainz = { type, alias }: {
                  urls = [
                    {
                      template = "https://musicbrainz.org/search";
                      params = [
                        (lib.nameValuePair "type" type)
                        (lib.nameValuePair "method" "indexed")
                        (lib.nameValuePair "query" "{searchTerms}")
                      ];
                    }
                  ];
                  definedAliases = [ alias ];
                };
              in
              {
                Amazon = {
                  urls = [ { template = "https://www.amazon.com/s?k={searchTerms}"; } ];
                  definedAliases = [ "az" ];
                  iconUpdateURL = "https://www.amazon.com/favicon.ico";
                };
                "Amazon FR" = {
                  urls = [ { template = "https://www.amazon.fr/s?k={searchTerms}"; } ];
                  definedAliases = [ "azf" ];
                  iconUpdateURL = "https://www.amazon.fr/favicon.ico";
                };
                "Arch Linux" = {
                  urls = [ { template = "https://wiki.archlinux.org/index.php?search={searchTerms}"; } ];
                  definedAliases = [ "aw" ];
                };
                "Bandcamp" = {
                  urls = [ { template = "https://bandcamp.com/search?q={searchTerms}"; } ];
                  definedAliases = [ "bc" ];
                  iconUpdateURL = "https://s4.bcbits.com/img/favicon/favicon-32x32.png";
                };
                "Click" = {
                  urls = [ { template = "https://click.palletsprojects.com/en/latest/search/?q={searchTerms}"; } ];
                  definedAliases = [
                    "click"
                    "pc"
                  ];
                  iconUpdateURL = "https://click.palletsprojects.com/en/latest/_static/click-icon.png";
                };
                "CTAN" = {
                  urls = [ { template = "https://ctan.org/search?phrase={searchTerms}"; } ];
                  definedAliases = [ "ctan" ];
                  iconUpdateURL = "http://www.ctan.org/images/favicon.ico";
                };
                "DuckDuckGo" = {
                  urls = [ { template = "https://duckduckgo.com/?q={searchTerms}"; } ];
                  definedAliases = [ "ddg" ];
                  iconUpdateURL = "https://duckduckgo.com/favicon.ico";
                };
                Discogs = {
                  urls = [ { template = "https://www.discogs.com/search?q={searchTerms}&type=all"; } ];
                  definedAliases = [ "discogs" ];
                };
                Emojipedia = {
                  urls = [ { template = "https://emojipedia.org/search?q={searchTerms}"; } ];
                  definedAliases = [ "emoji" ];
                };
                GitHub = {
                  urls = [ { template = "https://github.com/search?q={searchTerms}&type=repositories"; } ];
                  definedAliases = [ "gh" ];
                };
                "Google Maps" = {
                  urls = [ { template = "https://maps.google.com/?q={searchTerms}"; } ];
                  icon = "${pkgs.nixos-icons}/share/icons/hicolor/scalable/apps/nix-snowflake.svg";
                  definedAliases = [ "maps" ];
                };
                "IETF" = {
                  urls = [ { template = "https://datatracker.ietf.org/doc/search?name={searchTerms}&sort=&rfcs=on&activedrafts=on&by=group&group="; } ];
                  iconUpdateURL = "https://static.ietf.org/dt/12.34.0/ietf/images/ietf-logo-nor-180.png";
                  definedAliases = [ "ietf" ];
                };
                "Kagi" = {
                  urls = [ { template = "https://kagi.com/search?q={searchTerms}"; } ];
                  definedAliases = [ "k" ];
                  iconUpdateURL = "https://search-cdn.kagi.com/v1/favicon-32x32.png";
                };
                "Kagi FR" = {
                  urls = [ { template = "https://kagi.com/search?q={searchTerms}&r=fr"; } ];
                  definedAliases = [ "kf" ];
                  iconUpdateURL = "https://search-cdn.kagi.com/v1/favicon-32x32.png";
                };
                "Home-assistant discourse" = {
                  urls = [ { template = "https://community.home-assistant.io/search?&q={searchTerms}"; } ];
                  definedAliases = [ "hd" ];
                  iconUpdateURL = "https://www.home-assistant.io/images/favicon-192x192.png";
                };
                "Home-Manager options" = {
                  urls = [ { template = "https://home-manager-options.extranix.com/?query={searchTerms}"; } ];
                  icon = "${pkgs.nixos-icons}/share/icons/hicolor/scalable/apps/nix-snowflake.svg";
                  definedAliases = [ "nh" ];
                };
                "Manpages" = {
                  urls = [ { template = "https://man.archlinux.org/search?q={searchTerms}"; } ];
                  definedAliases = [ "man" ];
                };
                "MDN" = {
                  urls = [ { template = "https://developer.mozilla.org/en-US/search?q={searchTerms}"; } ];
                  icon = "${pkgs.nixos-icons}/share/icons/hicolor/scalable/apps/nix-snowflake.svg";
                  definedAliases = [ "mdn" ];
                };
                "MusicBrainz Artists" = searchMusicBrainz { type = "artist"; alias = "mba"; };
                "MusicBrainz Release (Album)" = searchMusicBrainz { type = "release"; alias = "mbr"; };
                "NixOS Discourse" = {
                  urls = [ { template = "https://discourse.nixos.org/search?q={searchTerms}"; } ];
                  icon = "${pkgs.nixos-icons}/share/icons/hicolor/scalable/apps/nix-snowflake.svg";
                  definedAliases = [ "nd" ];
                };
                "NixOS options" = {
                  urls = [ { template = "https://search.nixos.org/options?query={searchTerms}"; } ];
                  icon = "${pkgs.nixos-icons}/share/icons/hicolor/scalable/apps/nix-snowflake.svg";
                  definedAliases = [ "no" ];
                };
                "Nix Packages" = {
                  urls = [
                    {
                      template = "https://search.nixos.org/packages";
                      params = [
                        (lib.nameValuePair "type" "packages")
                        (lib.nameValuePair "query" "{searchTerms}")
                      ];
                    }
                  ];
                  icon = "${pkgs.nixos-icons}/share/icons/hicolor/scalable/apps/nix-snowflake.svg";
                  definedAliases = [ "np" ];
                };
                "NixOS Wiki" = {
                  urls = [ { template = "https://nixos.wiki/index.php?title=Special:Search&search={searchTerms}"; } ];
                  iconUpdateURL = "https://nixos.wiki/favicon.png";
                  definedAliases = [ "nw" ];
                };
                "Python" = {
                  urls = [ { template = "https://docs.python.org/3/search.html?q={searchTerms}"; } ];
                  iconUpdateURL = "https://docs.python.org/3/_static/py.svg";
                  definedAliases = [ "py" ];
                };
                "PyPI" = {
                  urls = [ { template = "https://pypi.org/search/?q={searchTerms}"; } ];
                  iconUpdateURL = "https://docs.python.org/3/_static/py.svg";
                  definedAliases = [
                    "pp"
                    "pypi"
                  ];
                };
                "RFC" = {
                  urls = [ { template = "https://datatracker.ietf.org/doc/html/rfc{searchTerms}"; } ];
                  iconUpdateURL = "https://static.ietf.org/dt/12.34.0/ietf/images/ietf-logo-nor-180.png";
                  definedAliases = [ "rfc" ];
                };
                "Rust docs" = {
                  urls = [ { template = "https://docs.rs/releases/search?query={searchTerms}"; } ];
                  iconUpdateURL = "https://www.rust-lang.org/static/images/favicon.svg";
                  definedAliases = [ "rd" ];
                };
                "Rust packages" = {
                  urls = [ { template = "https://crates.io/search?q={searchTerms}"; } ];
                  iconUpdateURL = "https://www.rust-lang.org/static/images/favicon.svg";
                  definedAliases = [ "rp" ];
                };
                "Rust stdlib" = {
                  urls = [ { template = "https://doc.rust-lang.org/std/index.html?search={searchTerms}"; } ];
                  iconUpdateURL = "https://www.rust-lang.org/static/images/favicon.svg";
                  definedAliases = [ "rs" ];
                };
                "Sphinx" = {
                  urls = [ { template = "https://www.sphinx-doc.org/en/master/search.html?q={searchTerms}"; } ];
                  iconUpdateURL = "	https://www.sphinx-doc.org/en/master/_static/favicon.svg";
                  definedAliases = [ "sphinx" ];
                };
                "Wikipedia FR" = {
                  urls = [ { template = "https://fr.wikipedia.org/w/index.php?search={searchTerms}"; } ];
                  iconUpdateURL = "https://fr.wikipedia.org/static/favicon/wikipedia.png";
                  definedAliases = [ "wf" ];
                };
                "Wikipedia EN" = {
                  urls = [ { template = "https://en.wikipedia.org/w/index.php?search={searchTerms}"; } ];
                  iconUpdateURL = "https://en.wikipedia.org/static/favicon/wikipedia.png";
                  definedAliases = [ "w" ];
                };
                "Wiktionary EN" = {
                  urls = [ { template = "https://en.wiktionary.org/w/index.php?search={searchTerms}"; } ];
                  definedAliases = [ "d" ];
                };
                "Wiktionary FR" = {
                  urls = [ { template = "https://fr.wiktionary.org/w/index.php?search={searchTerms}"; } ];
                  definedAliases = [ "df" ];
                };
                "WordReference EN → FR" = {
                  urls = [ { template = "https://www.wordreference.com/enfr/{searchTerms}"; } ];
                  iconUpdateURL = "https://www.wordreference.com/icon.svg";
                  definedAliases = [ "wef" ];
                };
                "WordReference FR → EN" = {
                  urls = [ { template = "https://www.wordreference.com/fren/{searchTerms}"; } ];
                  iconUpdateURL = "https://www.wordreference.com/icon.svg";
                  definedAliases = [ "wfe" ];
                };
                "YouTube" = {
                  urls = [ { template = "https://www.youtube.com/results?search_query={searchTerms}"; } ];
                  icon = "${pkgs.nixos-icons}/share/icons/hicolor/scalable/apps/nix-snowflake.svg";
                  definedAliases = [ "yt" ];
                };
              };
              search.force = true;
            };
          };
      };

      programs.git = {
        enable = true;
        userName = "Louis Opter";
        userEmail = "louis@opter.org";
        ignores = [
          # directories
          "debug/"
          ".devenv/"
          ".direnv/"
          "*.egg-info/"
          ".mypy_cache/"
          "node_modules/"
          "__pycache__/"
          "target/"

          # files
          "bazel-*"
          "result*"
          "Session.vim"
          ".ycm_extra_conf.py"
        ];
      };

      programs.gpg = {
        enable = true;
        publicKeys = [
          {
            source = ../../../config/louis-pubkey.gpg;
            trust = "ultimate";
          }
        ];
      };

      # Let Home Manager install and manage itself:
      programs.home-manager.enable = true;
      programs.mpv = {
        enable = true;
        scriptOpts = {
          ytdl_hook.ytdl_path = "${pkgs.yt-dlp}/bin/yt-dlp";
        };
      };
      programs.neovim = {
        # {{{
        enable = true;
        coc = {
          enable = true;
          settings = {
            "diagnostic.virtualText" = false;
            "inlayHint.position" = "eol";
            languageserver.nix = {
              command = "nixd";
              filetypes = [ "nix" ];
            };
          };
        };
        defaultEditor = true;
        vimAlias = true;
        withNodeJs = true;
        plugins = with pkgs.vimPlugins; [
          coc-go
          coc-pyright
          coc-rust-analyzer
          direnv-vim
          fzf-vim
          (nvim-treesitter.withPlugins (
            plugins: with plugins; [
              awk
              bash
              c
              cmake
              cpp
              diff
              dockerfile
              git_config
              git_rebase
              gitcommit
              gitignore
              go
              hcl
              json
              latex
              make
              markdown
              nix
              # pkgs.tree-sitter.buildGrammar {
              #   language = "orgmode";
              #   version = "2023-11-22";
              #   src = pkgs.fetchFromGitHub {
              #     owner = "nvim-orgmode";
              #     repo = "orgmode";
              #     rev = "cbb10d4c7514680e90f791d62f1168cb87aad0ce";
              #     sha256 = "";
              #   };
              #   meta.homepage = "https://nvim-orgmode.github.io/";
              # }
              python
              rust
              rst
              smali
              toml
              yaml
            ]
          ))
          vim-airline
          {
            plugin = vim-airline-themes;
            config = "let g:airline_theme = 'papercolor'";
          }
          vim-graphql
          vim-jinja
          vim-desert256
          # {
          #   plugin = vim-desert256;
          #   config = ''
          #     colorscheme desert256
          #   '';
          # }
          {
            plugin = vim-lucius;
            config = ''
              set background=light
              colorscheme lucius
              LuciusWhite

              hi link CocHintFloat DiagnosticHint
              hi link CocInfoFloat DiagnosticInfo
              hi link CocWarningFloat DiagnosticWarning
              hi link CocErrorFloat DiagnosticError

              let g:fzf_colors =
                \ { 'fg':         ['fg', 'Normal'],
                  \ 'bg':         ['bg', 'Normal'],
                  \ 'hl':         ['fg', 'Comment'],
                  \ 'fg+':        ['fg', 'CursorLine', 'CursorColumn', 'Normal'],
                  \ 'bg+':        ['bg', 'CursorLine', 'CursorColumn'],
                  \ 'hl+':        ['fg', 'Statement'],
                  \ 'info':       ['fg', 'PreProc'],
                  \ 'border':     ['fg', 'Ignore'],
                  \ 'prompt':     ['fg', 'Conditional'],
                  \ 'pointer':    ['fg', 'Exception'],
                  \ 'marker':     ['fg', 'Keyword'],
                  \ 'spinner':    ['fg', 'Label'],
                  \ 'header':     ['fg', 'Comment'] }
            '';
          }
          vim-signature
          {
            plugin = vim-sneak;
            config = "let g:sneak#label = 1"; # easy-motion like
          }
        ];
        extraConfig = ''
          set nocp
          set backspace=indent,eol,start
          set showmatch
          set nohlsearch
          set softtabstop=4
          set sw=4
          set expandtab
          set ruler
          set showmode
          set ul=200
          set cindent
          set autoindent
          set nobackup
          set history=50
          set wildmenu
          set ttyfast
          set incsearch
          set cursorline
          set nowrap
          set linebreak
          set laststatus=2 " Always show the statusline
          set encoding=utf-8
          set t_Co=256
          set title

          if has("mouse")
              set mouse=a
          endif

          if has("syntax")
              syntax on
          endif

          lua vim.opt.titlestring = [[%{fnamemodify(getcwd(), ":t")}/%f %h%m%r%w]]

          au BufRead,BufNewFile *.blt,*.rtx,*.cw[sp] set ft=c
          au BufRead,BufNewFile *.ino set ft=cpp
          au BufRead,BufNewFile *.rb set ts=2 sts=2 sw=2
          au BufRead,BufNewFile *.pp set ft=puppet
          au BufRead,BufNewFile *.go set ts=8 sts=8 sw=8 expandtab ft=go
          au BufRead,BufNewFile *.coffee set ts=2 sts=2 sw=2 ft=coffee
          au BufRead,BufNewFile *.jade set ts=2 sts=2 sw=2 ft=jade
          au BufRead,BufNewFile *.avsc set ts=2 sts=2 sw=2 ft=json
          au BufRead,BufNewFile *.nix set ts=2 sts=2 sw=2 ft=nix
          au BufRead,BufNewFile *.html,*.css set ts=2 sts=2 sw=2
          au BufRead,BufNewFile *.smali set ft=smali
          au BufRead,BufNewFile *.thrift set ft=thrift

          """ Functions

          function ToggleLineNumbers()
            let current_window = win_getid()
            let current_view = winsaveview()
            tabdo windo set invnumber
            call win_gotoid(current_window)
            call winrestview(current_view)
          endfunction

          function GithubPermalink()
            " Get the current filename and line number
            let current_file = expand("%")
            let current_line = line(".")

            " Get the git repository root directory
            let git_root = system("git rev-parse --show-toplevel")
            let git_root = substitute(git_root, '\n\+$', ''', ''')

            " Make the file path relative to the git repository root
            let relative_file_path = substitute(current_file, '^' . git_root . '/', ''', ''')

            " Get the GitHub URL of the current repository
            let github_url = system("git remote -v | awk '/github.com/ { print(\"https://github.com/\" gensub(/^git@github.com:(.+).git$/, \"\\\\1\", \"g\", $2) \"/\"); }' | tail -n1")
            let github_url = substitute(github_url, '\n\+$', ''', ''')

            " Get the commit SHA for origin/main
            let commit_sha = system("for each in {upstream,origin}/{master,main}; do { git rev-parse --quiet --verify --revs-only $each && break; }; done ")
            let commit_sha = substitute(commit_sha, '\n\+$', ''', ''')

            " Construct the GitHub permalink
            let github_permalink = github_url . "blob/" . commit_sha . "/" . relative_file_path . "#L" . current_line
            return github_permalink
          endfunction

          function CopyGithubPermalink()
            let github_permalink = GithubPermalink()
            call system('printf "' . github_permalink . '" | wl-copy')
          endfunction

          """ Mappings

          map Q gq
          map <Leader>t "*
          map <Leader>d "+
          map <silent> <Leader>n :call ToggleLineNumbers()<CR>
          map <silent> <Leader>l :call CopyGithubPermalink()<CR>
          map <silent> <Leader>h :set invhlsearch<CR>
          map <silent> <Leader>w :set invwrap<CR>
          vmap <silent> <Leader>s :'<,'>!sort<CR>
          nnoremap <silent> <C-j> :tabnext<CR>
          nnoremap <silent> <C-k> :tabprevious<CR>
          nnoremap <silent> <C-p> :Files<CR>
          nnoremap <silent> <C-b> :Buffers<CR>
        '';
        extraLuaConfig = ''
          require'nvim-treesitter.configs'.setup {
            highlight = {
              enable = true,
            },
          }
        '';
      }; # }}}
      programs.plasma = {
        enable = true;

        #
        # Some high-level settings:
        #
        workspace = {
          clickItemTo = "open"; # If you liked the click-to-open default from plasma 5
          lookAndFeel = "org.kde.breeze.desktop";
          cursor = {
            theme = "Bibata-Modern-Ice";
            size = 32;
          };
          iconTheme = "breeze";
          # wallpaperPlainColor = "0,0,0,0";
          wallpaper = "/stash/home/kal/cu/wp/banksy-tv-heads.jpg";
        };

        hotkeys.commands."launch-konsole" = {
          name = "Launch Konsole";
          key = "Meta+Space";
          command = "konsole";
        };

        fonts = {
          general = {
            family = "JetBrains Mono";
            pointSize = 12;
          };
          fixedWidth = {
            family = "Inconsolata";
            pointSize = 12;
          };
        };

        panels = [
          # {{{
          # Windows-like panel at the bottom
          {
            location = "bottom";
            screen = "all";
            widgets = [
              # We can configure the widgets by adding the name and config
              # attributes. For example to add the the kickoff widget and set the
              # icon to "nix-snowflake-white" use the below configuration. This will
              # add the "icon" key to the "General" group for the widget in
              # ~/.config/plasma-org.kde.plasma.desktop-appletsrc.
              # {
              #   name = "org.kde.plasma.kickoff";
              #   config = {
              #     General = {
              #       icon = "nix-snowflake-white";
              #       alphaSort = true;
              #     };
              #   };
              # }
              # Or you can configure the widgets by adding the widget-specific options for it.
              # See modules/widgets for supported widgets and options for these widgets.
              # For example:
              {
                kickoff = {
                  sortAlphabetically = true;
                  icon = "nix-snowflake-white";
                };
              }

              /*
                {
                  pager = {
                    general = {
                      selectingCurrentVirtualDesktop = "showDesktop";
                      displayedText = "none";
                    };
                  };
                }
              */

              # Adding configuration to the widgets can also for example be used to
              # pin apps to the task-manager, which this example illustrates by
              # pinning dolphin and konsole to the task-manager by default with widget-specific options.
              {
                iconTasks = {
                  launchers = [
                    /*
                          "applications:org.kde.konsole.desktop"
                          "applications:mindforger.desktop"
                          "applications:org.kde.dolphin.desktop"
                          "applications:io.github.Qalculate.qalculate-qt.desktop"
                          "applications:org.kde.gwenview.desktop"
                          "applications:org.kde.okular.desktop"
                          "applications:tidal-hifi.desktop"
                          "applications:firefox.desktop"
                          "applications:signal-desktop.desktop"
                          "applications:org.telegram.desktop.desktop"
                    */
                  ];
                };
              }

              # If no configuration is needed, specifying only the name of the
              # widget will add them with the default configuration.
              "org.kde.plasma.marginsseparator"
              # If you need configuration for your widget, instead of specifying the
              # the keys and values directly using the config attribute as shown
              # above, plasma-manager also provides some higher-level interfaces for
              # configuring the widgets. See modules/widgets for supported widgets
              # and options for these widgets. The widgets below shows two examples
              # of usage, one where we add a digital clock, setting 12h time and
              # first day of the week to Sunday and another adding a systray with
              # some modifications in which entries to show.
              {
                systemMonitor = {
                  displayStyle = "org.kde.ksysguard.barchart";
                  sensors = [
                    {
                      name = "cpu/all/usage";
                      color = "233,196,61";
                      label = "CPU %";
                    }
                    {
                      name = "memory/physical/usedPercent";
                      color = "233,61,187";
                      label = "MEM %";
                    }
                  ];
                };
              }
              {
                digitalClock = {
                  calendar.firstDayOfWeek = "sunday";
                  time.format = "24h";
                  timeZone = {
                    format = "offset";
                    selected = [
                      "America/Los_Angeles"
                      "America/New_York"
                      "Europe/Paris"
                      "UTC"
                    ];
                  };
                };
              }
              {
                systemTray.items = {
                  # We explicitly show bluetooth and battery
                  shown = [
                    "org.kde.plasma.battery"
                    "org.kde.plasma.bluetooth"
                    "org.kde.plasma.networkmanagement"
                    "org.kde.plasma.volume"
                  ];
                  # And explicitly hide networkmanagement and volume
                  hidden = [
                  ];
                };
              }
            ];
            hiding = "autohide";
          }
          # Application name, Global menu and Song information and playback controls at the top
          {
            location = "top";
            screen = "all";
            height = 26;
            widgets = [
              {
                applicationTitleBar = {
                  behavior = {
                    activeTaskSource = "activeTask";
                  };
                  layout = {
                    elements = [ "windowTitle" ];
                    horizontalAlignment = "left";
                    showDisabledElements = "deactivated";
                    verticalAlignment = "center";
                  };
                  overrideForMaximized.enable = false;
                  titleReplacements = [
                    {
                      type = "regexp";
                      originalTitle = "^Brave Web Browser$";
                      newTitle = "Brave";
                    }
                    {
                      type = "regexp";
                      originalTitle = ''\\bDolphin\\b'';
                      newTitle = "File manager";
                    }
                  ];
                  windowTitle = {
                    font = {
                      bold = false;
                      fit = "fixedSize";
                      size = 12;
                    };
                    hideEmptyTitle = true;
                    margins = {
                      bottom = 0;
                      left = 10;
                      right = 5;
                      top = 0;
                    };
                    source = "appName";
                  };
                };
              }
              "org.kde.plasma.appmenu"
              "org.kde.plasma.panelspacer"
              {
                plasmusicToolbar = {
                  panelIcon = {
                    albumCover = {
                      useAsIcon = false;
                      radius = 8;
                    };
                    icon = "view-media-track";
                  };
                  playbackSource = "auto";
                  musicControls.showPlaybackControls = true;
                  songText = {
                    displayInSeparateLines = false;
                    maximumWidth = 640;
                    scrolling = {
                      behavior = "alwaysScroll";
                      speed = 3;
                    };
                  };
                };
              }
            ];
          }
        ]; # }}}

        window-rules = [
          {
            description = "Dolphin";
            match = {
              window-class = {
                value = "dolphin";
                type = "substring";
              };
              window-types = [ "normal" ];
            };
            apply = {
              noborder = {
                value = true;
                apply = "force";
              };
              # `apply` defaults to "apply-initially"
              maximizehoriz = true;
              maximizevert = true;
            };
          }
        ];

        powerdevil =
          let
            AC = {
              powerButtonAction = "nothing";
              autoSuspend.action = "nothing";
              whenSleepingEnter = "standby";
              whenLaptopLidClosed = "sleep";
              turnOffDisplay.idleTimeout = "never";
            };
            battery = AC // {
              turnOffDisplay = {
                idleTimeout = 600;
                idleTimeoutWhenLocked = "immediately";
              };
              dimDisplay = {
                enable = true;
                idleTimeout = 60 * 5;
              };
            };
          in
          {
            inherit AC battery;
            lowBattery = battery // {
              autoSuspend = {
                idleTimeout = 60 * 10;
                action = "sleep";
              };
            };
          };

        kwin = {
          edgeBarrier = 0; # Disables the edge-barriers introduced in plasma 6.1
          effects.desktopSwitching.animation = "off";
          cornerBarrier = false;

          # The way tilling works with Polonium is so
          # far off i3 that I am better without it.
          scripts.polonium.enable = false;

          virtualDesktops = {
            rows = 1;
            number = 10;
          };
        };

        kscreenlocker = {
          lockOnResume = true;
          timeout = 10;
        };

        #
        # Some mid-level settings:
        #
        shortcuts =
          let
            repeat =
              action: shortcut: count:
              let
                mkEntry =
                  i:
                  let
                    n = i + 1;
                  in
                  {
                    name = "${action} ${toString n}";
                    value = "${shortcut}+${if n == 10 then "0" else toString n}";
                  };
                items = lib.genList mkEntry count;
              in
              lib.listToAttrs items;
          in
          {
            # Those seem to go under "system settings" as opposed to Applications
            # or Common Actions.
            "services/org.kde.krunner.desktop" = {
              "_launch" = "Meta+R";
            };
            ksmserver = {
              "Lock Session" = [
                "Favorites"
                "Eject"
              ];
            };
            kwin = {
              "Expose" = "Meta+,";
              "Window Fullscreen" = "Meta+F";
              "Window Maximize" = "Meta+M";
              "Switch Window Down" = "Meta+J";
              "Switch Window Left" = "Meta+H";
              "Switch Window Right" = "Meta+L";
              "Switch Window Up" = "Meta+K";
              "Window to Desktop 1" = "Meta+!";
              "Window to Desktop 2" = "Meta+@";
              "Window to Desktop 3" = "Meta+#";
              "Window to Desktop 4" = "Meta+$";
              "Window to Desktop 5" = "Meta+%";
              "Window to Desktop 6" = "Meta+^";
              "Window to Desktop 7" = "Meta+&";
              "Window to Desktop 8" = "Meta+*";
              "Window to Desktop 9" = "Meta+(";
              "Window to Desktop 10" = "Meta+)";
              "view_actual_size" = "Alt+0";
              "view_zoom_in" = "Alt++";
              "view_zoom_out" = "Alt+-";
            } // (repeat "Switch to Desktop" "Meta" 10);

            plasmashell = {
              "activate application launcher" = "Meta+O";
            } // (repeat "Activate Task Manager Entry" "Ctrl" 9);
          };

        #
        # Some low-level settings:
        #
        configFile = {
          baloofilerc."Basic Settings"."Indexing-Enabled" = false;
          kwinrc."org.kde.kdecoration2".ButtonsOnLeft = "SF";
          kwinrc.Desktops.Number = {
            value = 10;
            # Forces kde to not change this value (even through the settings app).
            immutable = true;
          };
          kscreenlockerrc = {
            Greeter.WallpaperPlugin = "org.kde.potd";
            # To use nested groups use / as a separator. In the below example,
            # Provider will be added to [Greeter][Wallpaper][org.kde.potd][General].
            "Greeter/Wallpaper/org.kde.potd/General".Provider = "bing";
          };
        };
      };

      programs.ssh = {
        enable = true;
        compression = true;
        controlMaster = "auto";
        controlPath = "/run/user/${toString usergroups.users."${user}".uid}/ssh/master-%r@%h:%p";
        controlPersist = "10m";
        forwardAgent = false;
        serverAliveInterval = 180;
        extraConfig = ''
          VisualHostKey yes
        '';
        matchBlocks = destiny-config.lib.sshMatchBlocks;
      };

      programs.tmux = {
        enable = true;
        extraConfig = ''
          set-window-option -g mode-keys emacs
          set-option -g history-limit 10000
          set -g escape-time 10
        '';
      };

      programs.zsh =
        let
          locale = "en_US.UTF-8";
          zshenv = {
            inherit locale;
            LANG = locale;
            LANGUAGE = locale;
            LC.CTYPE = locale;
            LC.NUMERIC = locale;
            LC.TIME = locale;
            LC.COLLATE = locale;
            LC.MONETARY = locale;
            LC.MESSAGES = locale;
            LC.PAPER = locale;
            LC.NAME = locale;
            LC.ADDRESS = locale;
            LC.TELEPHONE = locale;
            LC.MEASUREMENT = locale;
            LC.IDENTIFICATION = locale;

            EMAIL = "louis@opter.org";
            MANWIDTH = "80";
            MY_TMP = "/tmp/${user}/tmp";
            MY_BUILD = "/tmp/${user}/build";
            PAGER = ''"less -FRX"'';
            PASSWORD_STORE_X_SELECTION = "primary";
            PGTZ = "UTC";
            PULSE_SERVER = "rpi-sfo-arch.kalessin.fr";
            REPLYTO = "louis@opter.org";
            WINEDEBUG = "-all";
          };
        in
        {
          defaultKeymap = "emacs";
          enable = true;
          envExtra = attrsToEnvironmentString { attrs = zshenv; };
          history = {
            append = true;
            ignoreDups = true;
            size = 1000;
            save = 10000;
          };
          initExtra = ''
            setopt EXTENDED_GLOB

            ulimit -c unlimited
            ulimit -n 4096

            setopt HIST_REDUCE_BLANKS
            HIST_ARCHIVE_DIR="''${HOME}/archives/zsh"
            HIST_HOSTNAME="$(hostname -s)"
            zshaddhistory() {
              # NOTE: We should defer that to a more complex program that could write
              #       that in a more structured & append-only format and eventually offer
              #       more advanced features like archiving, securing and agreggating
              #       history through a central location.
              local histline=$1

              local year_month=$(date "+%Y-%m")
              local cur_dir="''${HIST_ARCHIVE_DIR}/''${year_month}"
              mkdir -p "''${cur_dir}"

              if [ $(print -rn "''${histline}" | grep -c "^[[:space:]]*$") -eq 0 ]; then
                  local cur_time=$(date "+%H:%M:%S%z")
                  local cur_file="''${year_month}-$(date "+%d")_''${USER}_''${HIST_HOSTNAME}.log"
                  print -rn "''${cur_time} ''${histline}" >> "''${cur_dir}/''${cur_file}"
              fi
            }

            PROMPT=$'%m:%j:%{\e[0;32m%}%~%{\e[0m%}%(?.%#.%{\e[1;34m%}%#%{\e[0m%}) '

            if [ -z "''${SSH_CONNECTION}" ]; then
              export EDITOR="nvim-qt --nofork"
            else
              export EDITOR="nvim"
            fi

            alias p="ipython"
            alias pu="pushd"
            alias po="popd"
            alias d="dirs -v"

            chelp() { cmake --help-command $1 | rst2html.py -q | lynx -stdin }

            pclip() { env PASSWORD_STORE_X_SELECTION=clipboard pass "$@" }
            compdef _pass pclip

            # TODO: add an option to forget the selection:
            clippy() { xclip "$@" }

            git() {
              { [ $# -eq 1 ] && [ "$1" = "root" ] ; } && {
                  command git rev-parse --show-toplevel;
                  return;
              }

              { [ $# -eq 1 ] && [ "$1" = "branch" ]; } && {
                  command git branch -vv;
                  return;
              }

              { [ "$1" = "diff" ] || [ "$1" = "show" ] ; } && {
                  local files="$(command git "$@" --name-only --format=)"
                  local total=$(echo "$files" | wc -l)
                  local lock_files=$(echo "$files" | awk '/.*\.lock/ { matched++ } BEGIN { matched = 0 } END { print matched }')

                  # Avoid empty output when only lock files changed
                  [ $lock_files -eq $total ] && {
                      command git "$@";
                  } || {
                      command git "$@" ":(exclude)*.lock";
                  }
                  return;
              }

              command git "$@";
            }

            ffmergeav() {
              [ $# -eq 3 ] || {
                  printf >&2 "Usage: ffmergeav audio video output\n";
                  return 1;
              }
              ffmpeg -i "$1" -i "$2" -c:a copy -c:v copy "$3"
            }

            firefox-dev() {
              mkdir -p "$MY_BUILD/firefox"
              firefox --new-instance --devtools --profile "$MY_BUILD/firefox"
            }

            nix-prefetch-github() {
              command nix-prefetch-github --no-deep-clone --nix "@"
            }

            tree() {
              command tree --dirsfirst --gitignore -FC "$@"
            }

            tl() {
              tree "$@" | less -FRX
            }

            # It says ls was aliased, even though home-manager does not set any default:
            unalias ls
            ls() {
              command ls -NFh --group-directories-first --color=auto "$@";
            }

            playing() {
              mpc \
                  -h "''${1:-"localhost"}" \
                  current \
                  -f "/me is playing %artist% :: %album% :: %title%" \
              | xclip
            }

            restart-agent() { gpgconf --kill gpg-agent; reload-agent }

            ssh-untrusted() {
              ssh -a                                  \
                  -o UserKnownHostsFile=/dev/null     \
                  -o GlobalKnownHostsFile=/dev/null   \
                  "$@"
            }

            scp-untrusted() {
              scp -o UserKnownHostsFile=/dev/null     \
                  -o GlobalKnownHostsFile=/dev/null   \
                  "$@"
            }

            mosh() {
              command mosh -p ${toString ports.mosh.from}:${toString ports.mosh.to} "$@"
            }
          '';
        };

      # This value determines the Home Manager release that your
      # configuration is compatible with. This helps avoid breakage
      # when a new Home Manager release introduces backwards
      # incompatible changes.
      #
      # You can update Home Manager without changing this value. See
      # the Home Manager release notes for a list of state version
      # changes in each release.
      home.stateVersion = "22.05";

      # Configure kdesu to use sudo:
      # qt.kde.settings.kdesurc = {
      #   "super-user-command"."super-user-command" = "sudo";
      # };

      services.lorri.enable = false;

      services.gpg-agent = {
        enable = true;
        enableBashIntegration = true;
        enableSshSupport = true;
        enableScDaemon = true;
        enableZshIntegration = true;
        pinentryPackage = pkgs.pinentry-qt;
      };

      xdg.userDirs = {
        enable = true;

        desktop = "/tmp/${user}/tmp";
        documents = "${config.home.homeDirectory}/archives";
        download = "/tmp/${user}/tmp";
        music = "/media/hsrv-sfo-ashpool/goinfre/music";
        pictures = "/stash/goinfre/photos";
        publicShare = "/stash/home/${user}/www";
        videos = "/stash/goinfre";
      };
    };

  clan-destiny.nixpkgs.unfreePredicates = [
    "discord"
    "vault"
  ];

  nix.gc.automatic = lib.mkForce false;

  security.sudo.extraConfig = ''
    ${user}   ALL=(ALL) ALL
  '';

  systemd.user.tmpfiles.users."${user}".rules = [
    "d /run/user/%U/ssh 0700 ${user} ${user} - -"
    "d /tmp/${user} 0700 ${user} ${user} - -"
    "d /tmp/${user}/tmp 0700 ${user} ${user} aA:26w -"
    "d /tmp/${user}/build 0700 ${user} ${user} - -"
  ];

  users.users."${user}" = {
    openssh.authorizedKeys.keys = [
      userAuthorizedSSHKey
    ];
  };

}

# vim: set fdm=marker:
