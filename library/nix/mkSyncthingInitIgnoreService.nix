lib: pkgs: userName:
let
  initScript = pkgs.writeShellScript "syncthing-ignores-init" ''
    [ $# -eq 1 ] || {
      printf >&2 "Usage: $0 USER_NAME\n";
      exit 1;
    }

    username="$1"
    stignore="/stash/home/$username/syncthing/.stignore"
    ignore_patterns="/stash/home/$username/syncthing/ignore-patterns.txt"

    umask 0077

    if ! [ -f "$stignore" ]
    then
      printf "#include ignore-patterns.txt\n" >"$stignore"
      chown "$username:$username" "$stignore"
    fi

    if ! [ -f "$ignore_patterns" ]
    then
      f="$(mktemp syncthing-ignores.XXXXXXXXXX)"
      cat >"$f" <<'EOF'
    // Vous pouvez ajouter vos propres modèles de fichiers à ignorer (ne pas synchroniser) ci-dessous.
    // Pour prendre effet, cette liste doit être importée depuis le fichier .stignore avec la directive : #include ignore-patterns.txt
    // Pour en savoir plus : https://docs.syncthing.net/users/ignoring.html
    (?d).DS_Store
    EOF
      chown "$username:$username" "$f"
      touch --date "1970-01-01T00:00:00Z" $f
      mv "$f" "$ignore_patterns"
    fi
  '';
in
{
  description = "Syncthing ignores files setup";
  before = [ "syncthing.service" ];
  wantedBy = [ "multi-user.target" ];
  serviceConfig = {
    RemainAfterExit = true;
    Type = "oneshot";
    ExecStart = "${initScript} ${lib.escapeShellArg userName}";
  };
}
