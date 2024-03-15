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
        --exec 'aptos move test --dev --skip-fetch-latest-git-deps;'
    }

    pub() {
      local example=0x$(aptos config show-profiles | jq -r '.Result.default.account')

      aptos move publish \
        --package-dir ../token-minter \
        --named-addresses minter=$example \
        --skip-fetch-latest-git-deps

      aptos move publish \
        --named-addresses example_permit=$example,minter=$example \
        --skip-fetch-latest-git-deps
    }
  '';
}
