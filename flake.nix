{
  description = "An open-source web comment engine, which adds discussion functionality to plain, boring web pages.";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    # TODO :: Figure out a reasonably automated way to update this
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
      # TODO :: get this from metadata or something so we don't have to update it manually
      release = "3.10.0";
    in {
      formatter = std.mapAttrs (system: pkgs: pkgs.nixfmt-rfc-style) nixpkgsFor;
      nixosModules.default = import ./nixos-module.nix self;
      overlays.default = final: prev: let
        std = final.lib;
        src = inputs.comentario;
        # they specify v20 in the docs: https://docs.comentario.app/en/installation/building/
        nodejs = final.nodejs_20;
        yarn = final.yarn.override {inherit nodejs;};
        yarnLock = "${src}/yarn.lock";
        meta = {
          homepage = "https://comentario.app/";
          license = std.licenses.mit;
          changelog = "https://gitlab.com/comentario/comentario/-/blob/v${release}/CHANGELOG.md?ref_type=tags";
          platforms = std.platforms.linux;
          sourceProvenance = [std.sourceTypes.fromSource];
        };
      in {
        comentario = final.buildGo123Module {
          pname = "comentario";
          version = feMeta.version;
          inherit src;
          proxyVendor = true;
          # TODO :: Is there a way to do this without hardcoding this hash?
          vendorHash = "sha256-mW0IgK9BaIU+j4Zncdu9XGOpgm2y8nUVT1qR0xIB5r0=";
          nativeBuildInputs = with final; [
            gitMinimal
            go-swagger
          ];
          # HACK :: fixes an issue described in this thread: https://discourse.nixos.org/t/go-go-generate-vendoring/17359
          # FIX :: Build the e2e plugin instead of skipping it (it's not necessary for normal function, but it is used for testing)
          postConfigure = ''
            echo '--- Running `go generate`... ---'
            git init -q # TODO :: is this git init necessary?
            go generate
            echo "--- Done generating. ---"
            echo "--- Cleaning source... ---"
            rm -r e2e/plugin
            echo "--- Done cleaning. ---"
          '';
          # `db` and `templates` are both used at runtime, so we need them somewhere in the output
          # TODO :: Is `lib/comentario` the best place to put these?
          postInstall = ''
            mkdir -p $out/lib/comentario
            cp -r db $out/lib/comentario
            cp -r templates $out/lib/comentario
          '';
          meta =
            meta
            // {
              description = "An open-source web comment engine.";
              mainProgram = "comentario";
            };
        };
        comentario-fe = final.stdenv.mkDerivation (let
          # we have to do some hacks to get openapi-generator to work without network access
          oag = final.openapi-generator-cli;
          oagVersionName = "openapi-generator-cli-${oag.version}";
          openapitoolsJson = std.recursiveUpdate (fromJSON (readFile "${src}/frontend/openapitools.json")) {
            # replacing this value lets us use the prebuilt version of openapi-generator-cli from nixpkgs
            # FIX :: check that the upstream-specified version is compatible with the nixpkgs version
            "generator-cli".version = oagVersionName;
          };
          # write the updated config out so we can use it later...
          openapitoolsUpdated = (final.formats.json {}).generate "openapitools.json" openapitoolsJson;
          # this is where we're gonna put a symlink to the nixpkgs version of OAG so that npm can find it later
          oagDir = "$out/node_modules/@openapitools/openapi-generator-cli/versions";
          # fetch all the dependencies of the comentario package
          deps = final.mkYarnModules {
            pname = "${feMeta.name}-modules";
            version = feMeta.version;
            packageJSON = "${src}/package.json";
            inherit nodejs yarnLock;
            # make sure we also get dependencies for sub-packages
            workspaceDependencies =
              map (ws: {
                pname = ws;
                packageJSON = "${src}/${ws}/package.json";
              })
              feMeta.workspaces;
            # write a symlink to OAG so we can use it when building the frontend (we have to symlink it here because, as far as I know, you can't tell OAG to check anywhere else)
            postBuild = ''
              mkdir -p ${oagDir}
              ln -sT ${oag}/share/java/${oagVersionName}.jar "${oagDir}/${oagVersionName}.jar"
            '';
          };
          # generate symlinks from the sub-package directories to their node_modules
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
              # the docs don't mention it, but this is also necessary
              hugo
              # this is so we can run OAG
              temurin-jre-bin
            ]);
          # write symlinks to the dependencies we fetched earlier, add `node_modules/.bin` to PATH so all the build tools can be found, update the openapitools config so it'll use the nixpkgs version of OAG, build the frontend
          installPhase = ''
            runHook preInstall

            ln -sT ${deps}/node_modules ./node_modules
            export PATH="$PWD/node_modules/.bin:$PATH"

            ${std.concatStringsSep "\n" wsLinks}

            rm frontend/openapitools.json
            ln -sT ${openapitoolsUpdated} frontend/openapitools.json
            yarn run --offline generate

            yarn run --offline build:prod

            mv build/frontend $out
            mv build/docs $doc

            runHook postInstall
          '';
          meta =
            meta
            // {
              description = "Comentario frontend.";
            };
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
