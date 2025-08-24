{
  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
  let
    system = "x86_64-linux";

    pkgs = import nixpkgs {
      inherit system;
    };

    pkgsCross = import nixpkgs {
      inherit system;
      crossSystem = {
        config = "aarch64-unknown-linux-gnu";
      };
    };

    reprepro = pkgs.stdenv.mkDerivation rec {
      name = "reprepro-${version}";
      version = "4.16.0";

      src = pkgs.fetchurl {
        url = "https://alioth.debian.org/frs/download.php/file/"
            + "4109/reprepro_${version}.orig.tar.gz";
        sha256 = "14gmk16k9n04xda4446ydfj8cr5pmzsmm4il8ysf69ivybiwmlpx";
      };

      nativeBuildInputs = [ pkgs.makeWrapper ];
      buildInputs = pkgs.lib.singleton (pkgs.gpgme.override { gnupg = pkgs.gnupg; })
                ++ (with pkgs; [ db libarchive bzip2 xz zlib ]);

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
        rev = "338d27a9fc124e085e14dfdcff875f71fd61ff14";
        sha256 = "sha256-Cr0pg/1IG7Zz4Kos9K3PRjG81EIefhk0sMKQM7p6x28=";
      };
      vendorHash = "sha256-NrZjORe/MjfbRDcuYVOGjNMCo1JGWvJDNVEPojI3L/g=";
    };

    mkosi-sandbox-rosetta-mount-rbind = pkgsCross.stdenv.mkDerivation {
      name = "mkosi-sandbox-rosetta-mount-rbind";

      src = ./rosetta-fix;

      buildInputs = [ pkgsCross.glibc.static ];

      buildPhase = ''
        $CC -static -Os -o bin mkosi-sandbox-mount-rbind.c
      '';

      installPhase = ''
        mkdir -p $out/bin
        cp bin $out/bin/mkosi-sandbox-rosetta-mount-rbind
      '';
    };

    mkosi = (pkgs.mkosi.override {
      extraDeps = with pkgs; [
        apt dpkg gnupg debootstrap
        squashfsTools dosfstools e2fsprogs mtools mustache-go
        cryptsetup util-linux zstd which qemu-utils parted
      ] ++ [ reprepro mkosi-sandbox-rosetta-mount-rbind ];
    }).overrideAttrs (oldAttrs: {
      # check out rosetta-fix/README.md for more details
      patches = (oldAttrs.patches or []) ++ [
        "${self}/rosetta-fix/mkosi-sandbox.patch"
      ];

      postPatch = (oldAttrs.postPatch or "") + ''
        MOUNT_RBIND_HEX=$(${pkgs.util-linux}/bin/hexdump -v -e '/1 "%02x"' \
          ${mkosi-sandbox-rosetta-mount-rbind}/bin/mkosi-sandbox-rosetta-mount-rbind)

        substituteInPlace mkosi/sandbox.py \
          --replace "PLACEHOLDER_HEX_CONTENT" "$MOUNT_RBIND_HEX"
      '';
    });
  in {
    devShells.${system}.default = pkgs.mkShell {
      nativeBuildInputs = [ mkosi measured-boot ];
      shellHook = ''
        mkdir -p mkosi.packages mkosi.cache mkosi.builddir ~/.cache/mkosi
      '';
    };
  };
}
