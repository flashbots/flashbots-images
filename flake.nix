{
  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

  outputs = {
    self,
    nixpkgs,
  }: let
    systems = ["x86_64-linux" "aarch64-linux"];

    perSystem = system: let
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
          rev = "ed23e96785ebfb1ff153503b01cfbfb10cffae67";
          sha256 = "sha256-jrHcAEp4OYmOMTJ1BWIULoqKycqqQBWIRLjhKmiZor4=";
        };
        vendorHash = "sha256-glOyRTrIF/zP78XGV+v58a1Bec6C3Fvc5c8G3PglzPM=";
      };

      mkosiTools = with pkgs; [
        apt
        dpkg
        gnupg
        debootstrap
        dosfstools
        e2fsprogs
        mtools
        gptfdisk
        util-linux
        zstd
        which
        qemu-utils
        parted
        jq
        reprepro
        systemd
        bash
        coreutils
        findutils
        gnused
        gnugrep
        gnutar
        gzip
        xz
        curl
        git
        patch
        ncurses
      ];
      mkosiToolsEnv = pkgs.buildEnv {
        name = "mkosi-tools";
        paths = mkosiTools;
      };
      mkosi-unwrapped =
        (pkgs.mkosi.override {
          extraDeps = mkosiTools;
        }).overrideAttrs (old: {
          src = pkgs.fetchFromGitHub {
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

      # Create a wrapper script that runs mkosi with unshare.
      # Unshare is needed to create files owned by multiple uids/gids.
      mkosi = pkgs.writeShellScriptBin "mkosi" ''
        exec ${pkgs.util-linux}/bin/unshare \
          --map-auto --map-root-user \
          --setuid=0 --setgid=0 \
          -- \
          env PATH="${mkosiToolsEnv}/bin" \
          ${mkosi-unwrapped}/bin/mkosi "$@"
      '';
    in {
      devShell = pkgs.mkShell {
        nativeBuildInputs = with pkgs; [
          mkosi
          measured-boot
          measured-boot-gcp
          bash
          curl
          git
        ];
        shellHook = ''
          mkdir -p mkosi.packages mkosi.cache mkosi.builddir ~/.cache/mkosi
          touch mkosi.builddir/mkosi.sources
        '';
      };
    };
  in {
    devShells = builtins.listToAttrs (map (system: {
      name = system;
      value.default = (perSystem system).devShell;
    }) systems);
  };
}
