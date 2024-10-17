# Nix Flake for Comentario

A [Nix](https://nixos.org/) flake packaging [Comentario](https://comentario.app/), an open-source comment engine.

## Usage

Import the nixpkgs overlay and NixOS module:
```nix
inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs";
    comentario = {
        url = "github:SignalWalker/nix.pkg.comentario";
        inputs.nixpkgs.follows = "nixpkgs";
    };
};
outputs = inputs @ {
    self,
    nixpkgs,
    comentario,
    ...
}: {
    nixosConfigurations."example" = nixpkgs.lib.nixosSystem {
        modules = [
            comentario.nixosModules.default
            ({config, pkgs, lib, ...}: {
                config = {
                    nixpkgs.overlays = [
                        comentario.overlays.default
                    ];
                };
             })
        ];
    };
};
```

Configure the service:
```nix
{ config, pkgs, lib, ...}: let
    com = config.services.comentario;
in {
    config = {
        services.comentario = {
            enable = true;
            # These are the environment variables defined in the Comentario docs: https://docs.comentario.app/en/configuration/backend/static/
            settings = {
                HOST = "localhost";
                PORT = 8080;
                BASE_URL = "https://${com.virtualHost.domain}";
                # The service will fail if the secrets file doesn't exist or isn't accessible at runtime.
                # Make sure to make it readable by the comentario user/group (`config.services.comentario.user`).
                SECRETS_FILE = "/etc/comentario/secrets.yaml";
            };
            virtualHost = {
                domain = "comments.website.example";
                # This enables a simple NGINX vhost.
                nginx.enable = true;
            };
        };
        services.nginx = {
            enable = true;
            virtualHosts.${com.virtualHost.domain} = {
                # SSL is optional
                enableACME = true;
                forceSSL = true;
            };
        };
    };
};
```
