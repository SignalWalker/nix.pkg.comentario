{
  description = "An open-source web comment engine, which adds discussion functionality to plain, boring web pages.";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    alejandra = {
      url = "github:kamadorueda/alejandra";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    comentario = {
      url = "gitlab:comentario/comentario?ref=v3.10.0";
      flake = false;
    };
  };
  outputs = inputs @ {
    self,
    nixpkgs,
    ...
  }:
    with builtins; let
      std = nixpkgs.lib;
      systems = [
        "aarch64-darwin"
        "aarch64-linux"
        "x86_64-darwin"
        "x86_64-linux"
      ];
      nixpkgsFor = std.genAttrs systems (system:
        import nixpkgs {
          localSystem = builtins.currentSystem or system;
          crossSystem = system;
          overlays = [self.overlays.default];
        });
      feMeta = fromJSON (readFile "${inputs.comentario}/package.json");
    in {
      formatter = std.mapAttrs (system: pkgs: pkgs.default) inputs.alejandra.packages;
      nixosModules.default = import ./nixos-module.nix self;
      overlays.default = final: prev: let
        std = final.lib;
      in {
        comentario = final.buildGo123Module {
          pname = "comentario";
          version = feMeta.version; # from .goreleaser.yml
          src = inputs.comentario;
          proxyVendor = true;
          vendorHash = "sha256-mW0IgK9BaIU+j4Zncdu9XGOpgm2y8nUVT1qR0xIB5r0=";
          nativeBuildInputs = with final; [
            gitMinimal
            go-swagger
          ];
          # HACK :: fixes an issue described in this thread: https://discourse.nixos.org/t/go-go-generate-vendoring/17359
          postConfigure = ''
            echo '--- Running `go generate`... ---'
            git init -q # TODO :: is this git init necessary?
            go generate
            echo "--- Done generating. ---"
            echo "--- Cleaning source... ---"
            rm -r e2e/plugin
            echo "--- Done cleaning. ---"
          '';
        };
        comentario-fe = final.mkYarnPackage {
          pname = "comentario-fe";
          version = feMeta.version;
          src = inputs.comentario;
        };
      };
      packages =
        std.mapAttrs (system: pkgs: {
          inherit (pkgs) comentario comentario-fe;
          default = self.packages.${system}.comentario;
        })
        nixpkgsFor;
      devShells =
        std.mapAttrs (system: pkgs: let
          selfPkgs = self.packages.${system};
          stdenv = stdenvFor pkgs;
        in {
          default = (pkgs.mkShell.override {inherit stdenv;}) {
            stdenv = stdenvFor.${system};
            inputsFrom = [selfPkgs.default];
          };
        })
        nixpkgsFor;
    };
}
