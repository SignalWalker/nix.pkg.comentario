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
        src = inputs.comentario;
        nodejs = final.nodejs_20;
        yarn = final.yarn.override {inherit nodejs;};
        yarnLock = "${src}/yarn.lock";
      in {
        comentario = final.buildGo123Module {
          pname = "comentario";
          version = feMeta.version;
          inherit src;
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
          postInstall = ''
            mkdir -p $out/lib/comentario
            cp -r db $out/lib/comentario
            cp -r templates $out/lib/comentario
          '';
        };
        comentario-fe = final.stdenv.mkDerivation (let
          oag = final.openapi-generator-cli;
          oagVersionName = "openapi-generator-cli-${oag.version}";
          openapitoolsJson = std.recursiveUpdate (fromJSON (readFile "${src}/frontend/openapitools.json")) {
            "generator-cli".version = oagVersionName;
          };
          openapitoolsUpdated = (final.formats.json {}).generate "openapitools.json" openapitoolsJson;
          oagDir = "$out/node_modules/@openapitools/openapi-generator-cli/versions";
          deps = final.mkYarnModules {
            pname = "${feMeta.name}-modules";
            version = feMeta.version;
            packageJSON = "${src}/package.json";
            inherit nodejs yarnLock;
            workspaceDependencies =
              map (ws: {
                pname = ws;
                packageJSON = "${src}/${ws}/package.json";
              })
              feMeta.workspaces;
            postBuild = ''
              mkdir -p ${oagDir}
              ln -sT ${oag}/share/java/${oagVersionName}.jar "${oagDir}/${oagVersionName}.jar"
            '';
          };
          generatedApi = final.stdenv.mkDerivation (let
            cacert = final.cacert;
          in {
            pname = "${feMeta.name}-generated-api";
            version = feMeta.version;
            nativeBuildInputs =
              [nodejs yarn cacert oag]
              ++ (with final; [
                temurin-jre-bin
              ]);
            inherit src;
            # outputHashAlgo = "sha256";
            # outputHashMode = "recursive";
            # outputHash = "sha256-OGnTgnVj7gAEc1ME75j5ogOonP4Bm8hWmKVS6hIjHEc=";
            GIT_SSL_CAINFO = "${cacert}/etc/ssl/certs/ca-bundle.crt";
            NODE_EXTRA_CA_CERTS = "${cacert}/etc/ssl/certs/ca-bundle.crt";
            installPhase = ''
              runHook preInstall

              ln -sT ${deps}/node_modules ./node_modules
              export PATH="$PWD/node_modules/.bin:$PATH"

              rm frontend/openapitools.json
              ln -sT ${openapitoolsUpdated} frontend/openapitools.json

              yarn run --offline generate
              mv frontend/generated-api $out

              runHook postInstall
            '';
          });
          wsLinks = map (ws: "ln -sT ${deps}/deps/${ws}/node_modules ${ws}/node_modules") feMeta.workspaces;
        in {
          pname = feMeta.name;
          version = feMeta.version;
          inherit nodejs src;
          outputs = ["out" "doc"];
          nativeBuildInputs =
            [
              nodejs
              yarn
            ]
            ++ (with final; [
              hugo
              temurin-jre-bin
            ]);
          installPhase = ''
            runHook preInstall

            ln -sT ${deps}/node_modules ./node_modules
            export PATH="$PWD/node_modules/.bin:$PATH"

            ${std.concatStringsSep "\n" wsLinks}

            rm frontend/openapitools.json
            ln -sT ${openapitoolsUpdated} frontend/openapitools.json
            yarn run --offline generate

            # ln -sT ${generatedApi} frontend/generated-api
            # ls -lha frontend/generated-api

            yarn run --offline build:prod

            mv build/frontend $out
            mv build/docs $doc

            runHook postInstall
          '';
        });
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
        in {
          default = pkgs.mkShell {
            inputsFrom = [selfPkgs.comentario-fe];
            nativeBuildInputs = with pkgs; [
            ];
            shellHook = ''
              export PATH="$PWD/node_modules/.bin:$PATH"
            '';
          };
        })
        nixpkgsFor;
    };
}
