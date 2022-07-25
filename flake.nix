{
  description = "JSON representation of all cabal files from hackage";

  inputs = {
    nixpkgs.url = "nixpkgs/nixos-unstable";
    all-cabal-files.url = "github:commercialhaskell/all-cabal-files/hackage";
    all-cabal-files.flake = false;
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils, all-cabal-files }:
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
          targetFile=~/repos/all-cabal-json/$targetFolder/''${cabalFile%.*}.json
          echo "creating: $targetFile"
          mkdir -p $(dirname $targetFile)
          ${pkgs.haskellPackages.cabal2json}/bin/cabal2json $cabalFile | ${pkgs.jq}/bin/jq . > $targetFile
        '';

        updater = pkgs.writeScript "update-all-cabal-json" ''
          #!/usr/bin/env bash
          set -eou pipefail

          indexRevPrev=$(nix flake metadata --json | jq -e --raw-output '.locks.nodes."all-cabal-files".locked.rev')
          nix flake lock --update-input "all-cabal-files"
          indexRev=$(nix flake metadata --json | jq -e --raw-output '.locks.nodes."all-cabal-files".locked.rev')
          if [ "$indexRevPrev" == "$indexRev" ]; then
            echo "Index unchanged. Nothing to do. Exiting..."
            exit 0
          fi

          if [ $# -eq 0 ]
          then
            echo "Please provide output folder as argument."
            exit 1
          fi

          targetFolder=$1

          cd ${all-cabal-files}
          ${pkgs.parallel}/bin/parallel \
            --halt now,fail,1 \
            -a <(${pkgs.findutils}/bin/find . -type f -name '*.cabal') \
            ${converter} {} $targetFolder
        '';
      in
      {
        packages.default = updater;
        apps. default = {
          type = "app";
          program = "${updater}";
        };
      }
    );
}
