{ stdenv, fetchurl, lib, unzip }:

let
  os =
    if stdenv.isDarwin then "MacOSX"
    else if stdenv.isLinux then "Ubuntu"
    else throw "Unsupported platform ${stdenv.system}";

  sha256 = if os == "MacOSX" then "sha256-E7MtO+zBTL0hmoeeM29+SkQuZ201hh8Q8CrMrCLmvEQ="
            else "sha256-AwRYnhvTjUEKmFcENPXg18RNAWbLOajEmMJVgCBvT0k=";

in stdenv.mkDerivation rec {
  pname = "aptos-cli";
  version = "2.1.0";

  src = fetchurl {
    url = "https://github.com/aptos-labs/aptos-core/releases/download/${pname}-v${version}/${pname}-${version}-${os}-x86_64.zip";
    sha256 = sha256;
  };

  buildInputs = [ unzip ];

  unpackPhase = ''
    unzip $src
  '';

  installPhase = ''
    mkdir -p $out/bin
    cp aptos $out/bin/aptos
  '';

  meta = with lib; {
    description = "Aptos CLI";
    homepage = "https://github.com/aptos-labs/aptos-core";
    platforms = [ "x86_64-darwin" "aarch64-darwin" "x86_64-linux" "aarch64-linux" ];
  };
}
