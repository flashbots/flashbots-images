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
    mkosi = system: let
      pkgsForSystem = import nixpkgs {inherit system;};
      mkosi-unwrapped = pkgsForSystem.mkosi.override {
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
            util-linux
            zstd
            which
            qemu-utils
            parted
          ]
          ++ [reprepro];
      };
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
        nativeBuildInputs = [(mkosi system) measured-boot];
        shellHook = ''
          mkdir -p mkosi.packages mkosi.cache mkosi.builddir ~/.cache/mkosi
        '';
      };
    }) ["x86_64-linux" "aarch64-linux"]);
  };
}
