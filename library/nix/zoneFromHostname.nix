# Maye you could make this a vars?
hostname:
let
  knownZones = [
    "cdg"
    "cfr"
    "sfo"
  ];
  capturePattern = builtins.concatStringsSep "|" knownZones;
  groups = builtins.match ".+(${capturePattern})(-.+)?$" hostname;
in
  if groups == null then
    builtins.warn "Could not recognize zone in hostname `${hostname}`" null
  else
    builtins.elemAt groups 0
