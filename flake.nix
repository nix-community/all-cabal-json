{
  description = "JSON representation of all cabal files from hackage";

  inputs = {
    nixpkgs.url = "nixpkgs/nixos-unstable";
    all-cabal-hashes.url = "github:commercialhaskell/all-cabal-hashes/hackage";
    all-cabal-hashes.flake = false;
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils, all-cabal-hashes }:
    flake-utils.lib.eachSystem [ flake-utils.lib.system.x86_64-linux ] (system:
      let
        overlay = final: prev: {
          haskellPackages = prev.haskell.packages.ghc8107.override {
            overrides = hFinal: hPrev: {
              cabal2json = final.haskell.lib.dontCheck (final.haskell.lib.markUnbroken hPrev.cabal2json);
              autodocodec = final.haskell.lib.dontCheck (hPrev.autodocodec);
            };
          };
        };
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ overlay ];
        };
        l = pkgs.lib // builtins;

        converter = pkgs.writeScript "convert-cabal-to-json" ''
          set -eou pipefail

          cabalFile=$1
          targetFolder=$2
          cabalHashesJson=''${cabalFile%.*}.json
          targetFile=$targetFolder/''${cabalFile%.*}.json

          # create target dir
          mkdir -p $(dirname $targetFile)

          # copy hashes json file
          if [ -e $cabalHashesJson ]; then
            cp $cabalHashesJson $targetFolder/''${cabalFile%.*}.hashes.json
          fi

          echo "creating: $targetFile"
          ${pkgs.haskellPackages.cabal2json}/bin/cabal2json $cabalFile | ${pkgs.jq}/bin/jq . > $targetFile
        '';

        updater = pkgs.writeScriptBin "update-all-cabal-json" ''
          #!/usr/bin/env bash
          set -eou pipefail

          currFolder=$PWD

          cd ${all-cabal-hashes}
          ${pkgs.parallel}/bin/parallel \
            --halt now,fail,1 \
            -a <(${pkgs.findutils}/bin/find . -type f -name '*.cabal') \
            ${converter} {} $currFolder
        '';

      in
      {
        packages.default = updater;
        defaultApp = updater;
      }
    );
}
