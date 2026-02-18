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
        rev = "503e7c506f89f9d81be04025c90921778b26f0a4";
        sha256 = "sha256-z6STTgcOXatiqA2rlpzwRyvAwnXrK30oNDCJqtIp7/8=";
      };
      vendorHash = "sha256-glOyRTrIF/zP78XGV+v58a1Bec6C3Fvc5c8G3PglzPM=";
    };
    mkosi = system: let
      pkgsForSystem = import nixpkgs {inherit system;};
      mkosi-unwrapped = (pkgsForSystem.mkosi.override {
        extraDeps = with pkgsForSystem;
          [
            apt
            dpkg
            gnupg
            debootstrap
            squashfsTools
            dosfstools
            e2fsprogs
            mtools
            mustache-go
            cryptsetup
            gptfdisk
            util-linux
            zstd
            which
            qemu-utils
            parted
            unzip
            jq
          ]
          ++ [reprepro];
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
        postPatch = let fd = "${pkgs.patchutils}/bin/filterdiff"; in ''
          { ${fd} -x '*/run.py' --hunks=x2   ${builtins.elemAt old.patches 0}
            ${fd} -i '*/run.py' --hunks=x1-2 ${builtins.elemAt old.patches 0}
            ${fd} --hunks=x1                 ${builtins.elemAt old.patches 1}
          } | patch -p1
        '';
      });
    in
      # Create a wrapper script that runs mkosi with unshare
      # Unshare is needed to create files owned by multiple uids/gids
      pkgsForSystem.writeShellScriptBin "mkosi" ''
        exec ${pkgsForSystem.util-linux}/bin/unshare \
          --map-auto --map-current-user \
          --setuid=0 --setgid=0 \
          -- \
          env PATH="$PATH" \
          ${mkosi-unwrapped}/bin/mkosi "$@"
      '';
  in {
    devShells = builtins.listToAttrs (map (system: {
      name = system;
      value.default = pkgs.mkShell {
        nativeBuildInputs = [(mkosi system) measured-boot measured-boot-gcp];
        shellHook = ''
          mkdir -p mkosi.packages mkosi.cache mkosi.builddir ~/.cache/mkosi
          touch mkosi.builddir/mkosi.sources
        '';
      };
    }) ["x86_64-linux" "aarch64-linux"]);
  };
}
