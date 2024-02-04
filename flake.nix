{
  description = "lisp development environment";

  # assume 'nixpkgs'
  #inputs = { nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable"; };

  outputs = { self, nixpkgs }:
    let
      allSystems = [
        "x86_64-linux" # AMD/Intel Linux
        "x86_64-darwin" # AMD/Intel macOS
        "aarch64-linux" # ARM Linux
        "aarch64-darwin" # ARM macOS
      ];

      forAllSystems = fn:
        nixpkgs.lib.genAttrs allSystems
        (system: fn { pkgs = import nixpkgs { inherit system; }; });

    in {
      # used when calling `nix fmt <path/to/flake.nix>`
      formatter = forAllSystems ({ pkgs }: pkgs.nixfmt);

      # nix develop <flake-ref>#<name>
      # -- 
      # $ nix develop <flake-ref>#blue
      # $ nix develop <flake-ref>#yellow
      devShells = forAllSystems ({ pkgs }: {
        default = pkgs.mkShell {
          name = "cl";
          buildInputs = with pkgs; [ sbcl mutagen zstd.out ];
          # library which SBCL uses to compress images
          DPL_COMPRESSION_LIB = "${pkgs.zstd.out}/lib/libzstd.so";
          LD_LIBRARY_PATH = [
            # make library available for dynamic loading
            #"${pkgs.foo.out}/lib"
          ];
        };
      });
    };
}
