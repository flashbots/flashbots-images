{
  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

  outputs = {
    self,
    nixpkgs,
  }: let
    systems = ["x86_64-linux" "aarch64-linux"];

    perSystem = system: let
      pkgs = import nixpkgs {inherit system;};

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
        rev = "c17eca07bfd55539805dda2bb1add4cf0b32df12";
        hash = "sha256-sLJg4vf29HZF5ZHfmwPmbCmOXDHsJnsaz8dhfIfmvLE=";
      };
      attest = pkgs.rustPlatform.buildRustPackage {
        pname = "attest";
        version = "0.0.1";
        src = attest-src;
        cargoLock = {
          lockFile = "${attest-src}/Cargo.lock";
          outputHashes = {
            "dcap-qvl-0.3.12" = "sha256-rLTp5wIhXRAcBtJb7lfd1TAg7yPRnwa0cBa1YT4LwKU=";
            "cc-eventlog-0.5.8" = "sha256-KEauakj53LrhKTc0yYp5SM8ec0cFNm4YVuHCJYiPQjw=";
          };
        };
        cargoBuildFlags = ["-p" "attest-cli" "--no-default-features"];
        cargoTestFlags = ["-p" "attest-cli" "--no-default-features"];
      };

      # TODO: remove this and replace by apt 3.3.6 from upstream nixpkgs
      apt =
        if pkgs.lib.versionAtLeast pkgs.apt.version "3.3.6"
        then pkgs.apt
        else
          pkgs.apt.overrideAttrs (old: {
            version = "3.3.6";
            src = pkgs.fetchFromGitLab {
              domain = "salsa.debian.org";
              owner = "apt-team";
              repo = "apt";
              rev = "3.3.6";
              hash = "sha256-alH3LIew/Jh3v7ro319Wop5XvLqWeOUeTqhIkhd9rig=";
            };
            # Hegel tests git-clone at configure time; Debian's debian/rules disables them too
            cmakeFlags = old.cmakeFlags ++ [(pkgs.lib.cmakeBool "WITH_HEGEL_TESTS" false)];
          });

      mkosiTools = with pkgs; [
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
      mkosiToolsEnv = pkgs.buildEnv {
        name = "mkosi-tools";
        paths = mkosiTools;
      };
      mkosi-unwrapped = pkgs.mkosi.overrideAttrs (old: {
        postPatch =
          old.postPatch
          + ''
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
          ${mkosi-unwrapped}/bin/mkosi --sandbox-tree=${pkgs.debian-archive-keyring}/share/keyrings:/usr/share/keyrings "$@"
      '';
    in {
      devShell = pkgs.mkShell {
        nativeBuildInputs = with pkgs; [
          mkosi
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
    };
  in {
    devShells = builtins.listToAttrs (map (system: {
      name = system;
      value.default = (perSystem system).devShell;
    }) systems);
  };
}
