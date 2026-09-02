{
  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

  outputs = {
    self,
    nixpkgs,
  }: let
    system = "x86_64-linux";
    pkgs = import nixpkgs {inherit system;};
    reprepro = pkgs.stdenv.mkDerivation rec {
      name = "reprepro-${version}";
      version = "4.16.0";

      src = pkgs.fetchurl {
        url =
          "https://alioth.debian.org/frs/download.php/file/"
          + "4109/reprepro_${version}.orig.tar.gz";
        sha256 = "14gmk16k9n04xda4446ydfj8cr5pmzsmm4il8ysf69ivybiwmlpx";
      };

      nativeBuildInputs = [pkgs.makeWrapper];
      buildInputs =
        pkgs.lib.singleton (pkgs.gpgme.override {gnupg = pkgs.gnupg;})
        ++ (with pkgs; [db libarchive bzip2 xz zlib]);

      postInstall = ''
        wrapProgram "$out/bin/reprepro" --prefix PATH : "${pkgs.gnupg}/bin"
      '';
    };
    measured-boot = pkgs.buildGoModule {
      pname = "measured-boot";
      version = "main";
      src = pkgs.fetchFromGitHub {
        owner = "flashbots";
        repo = "measured-boot";
        rev = "v1.2.0";
        sha256 = "sha256-FjzJ6UQYyrM+U3OCMBpzd1wTxlikA5LI+NKrylGlG3c=";
      };
      vendorHash = "sha256-NrZjORe/MjfbRDcuYVOGjNMCo1JGWvJDNVEPojI3L/g=";
    };
    measured-boot-gcp = pkgs.buildGoModule {
      pname = "measured-boot-gcp";
      version = "main";
      src = pkgs.fetchFromGitHub {
        owner = "flashbots";
        repo = "dstack-mr-gcp";
        rev = "b16e08b32b3dc8f1af7087e12f9970dc91a0b9a0";
        sha256 = "sha256-3KIKgWsDzmLXuRK9YVxX2zJ6jAlZSmRm/bLYE1kJY7k=";
      };
      vendorHash = "sha256-glOyRTrIF/zP78XGV+v58a1Bec6C3Fvc5c8G3PglzPM=";
    };
    attest-src = pkgs.fetchFromGitHub {
      owner = "Easy-TEE";
      repo = "attest";
      rev = "e7f59c78f9eabd5d1ac7c9e96da46027878d038c";
      hash = "sha256-4PKNsN8j2P6YJfzghz0U28+Bm3BhS/CveR/mSx3oUg8=";
    };
    attest = pkgs.rustPlatform.buildRustPackage {
      pname = "attest";
      version = "0.0.1";
      src = attest-src;
      cargoDeps = (pkgs.rustPlatform.importCargoLock.override {
        fetchurl = args:
          pkgs.fetchurl (args
            // {
              url = builtins.replaceStrings
                ["https://crates.io/api/v1/crates"]
                ["https://static.crates.io/crates"]
                args.url;
            });
      }) {
        lockFile = "${attest-src}/Cargo.lock";
        outputHashes = {
          "dcap-qvl-0.3.12" = "sha256-rLTp5wIhXRAcBtJb7lfd1TAg7yPRnwa0cBa1YT4LwKU=";
          "cc-eventlog-0.5.8" = "sha256-KEauakj53LrhKTc0yYp5SM8ec0cFNm4YVuHCJYiPQjw=";
        };
      };
      cargoBuildFlags = ["-p" "attest-cli" "--no-default-features"];
      cargoTestFlags = ["-p" "attest-cli" "--no-default-features"];
    };
    mkosi = system: let
      pkgsForSystem = import nixpkgs {inherit system;};
      mkosiTools = with pkgsForSystem; [
        apt
        dpkg
        gnupg
        debootstrap
        dosfstools
        e2fsprogs
        erofs-utils
        mtools
        gptfdisk
        binutils
        util-linux
        zstd
        which
        qemu-utils
        parted
        jq
        syft
        reprepro
        systemd
        bash
        coreutils
        findutils
        gnused
        gnugrep
        gawk
        gnutar
        gzip
        xz
        curl
        git
        patch
        ncurses
      ];
      mkosiToolsEnv = pkgsForSystem.buildEnv {
        name = "mkosi-tools";
        paths = mkosiTools;
      };
      mkosi-unwrapped =
        (pkgsForSystem.mkosi.override {
          extraDeps = mkosiTools;
        }).overrideAttrs (old: {
          src = pkgsForSystem.fetchFromGitHub {
            owner = "systemd";
            repo = "mkosi";
            rev = "df51194bc2d890d4c267af644a1832d2d53339ac";
            hash = "sha256-rGGzE9xIR8WvK07GBnaAmeLpmnM3Uy51wqyrmuHuWXo=";
          };
          # TODO: remove these patch hunks from upstream nixpkgs next time mkosi has a release
          # The latest mkosi doesn't need them
          patches = pkgs.lib.drop 2 old.patches;
          postPatch = let
            fd = "${pkgs.patchutils}/bin/filterdiff";
          in ''
            { ${fd} -x '*/run.py' --hunks=x2   ${builtins.elemAt old.patches 0}
              ${fd} -i '*/run.py' --hunks=x1-2 ${builtins.elemAt old.patches 0}
              ${fd} --hunks=x1                 ${builtins.elemAt old.patches 1}
            } | patch -p1

            # Don't add /usr/bin and /usr/sbin to the PATH, only use /nix
            sed -i -E '\#^\s+"/usr/(bin|sbin)",$#d' mkosi/run.py
          '';
        });
    in
      # Create a wrapper script that runs mkosi with unshare
      # Unshare is needed to create files owned by multiple uids/gids
      pkgsForSystem.writeShellScriptBin "mkosi" ''
        exec ${pkgsForSystem.util-linux}/bin/unshare \
          --map-auto --map-root-user \
          --setuid=0 --setgid=0 \
          -- \
          env PATH="${mkosiToolsEnv}/bin" \
          ${mkosi-unwrapped}/bin/mkosi "$@"
      '';
  in {
    devShells = builtins.listToAttrs (map (system: {
      name = system;
      value.default = pkgs.mkShell {
        nativeBuildInputs = with pkgs; [
          (mkosi system)
          measured-boot
          measured-boot-gcp
          attest
          bash
          curl
          git
        ];
        shellHook = ''
          mkdir -p mkosi.packages mkosi.cache mkosi.builddir ~/.cache/mkosi
          touch mkosi.builddir/mkosi.sources
        '';
      };
    }) ["x86_64-linux" "aarch64-linux"]);
  };
}
