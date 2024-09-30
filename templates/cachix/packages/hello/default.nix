# NOTE: this package is derived from a flake-parts template
{
  stdenv,
  lib,
  runtimeShell,
}:
let
  inherit (lib.fileset) toSource unions;
in
stdenv.mkDerivation {
  name = "hello";
  src = toSource {
    root = ./.;
    fileset = unions [
      ./hello.sh
    ];
  };
  buildPhase = ''
    substitute hello.sh hello --replace '@shell@' ${runtimeShell}
    cat hello
    chmod a+x hello
  '';
  installPhase = ''
    install -D hello "$out/bin/hello"
  '';
  meta.mainProgram = "hello";
}
