with import <nixpkgs> { };

pkgs.mkShell {
  buildInputs = [
    jq
    nodePackages.nodemon
    nodejs_18
    (callPackage ../aptos.nix { })
  ];

  shellHook = ''
    alias gen="aptos init"

    test() {
      nodemon \
        --ignore build/* \
        --ext move \
        --exec 'aptos move test --dev --skip-fetch-latest-git-deps --ignore-compile-warnings --ignore-compile-warnings;'
    }
  '';
}
