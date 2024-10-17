self: {
  config,
  pkgs,
  lib,
  ...
}:
with builtins; let
  std = pkgs.lib;
  com = config.services.comentario;
in {
  options = with lib; {
    services.comentario = {
      enable = mkEnableOption "comentario";
      package = {
        backend = mkPackageOption pkgs "comentario" {};
        frontend = mkPackageOption pkgs "comentario-fe" {};
      };
      user = mkOption {
        type = types.str;
        description = "The user as which the Comentario backend service will run.";
        default = "comentario";
      };
      group = mkOption {
        type = types.str;
        description = "The group as which the Comentario backend service will run.";
        default = "comentario";
      };
      dir = {
        state = mkOption {
          type = types.str;
          readOnly = true;
          default = "/var/lib/${com.user}";
        };
        runtime = mkOption {
          type = types.str;
          readOnly = true;
          default = "/run/${com.user}";
        };
        configuration = mkOption {
          type = types.str;
          readOnly = true;
          default = "/etc/${com.user}";
        };
      };
      settings = mkOption {
        description = "Environment variables set for the Comentario service, as documented [here](https://docs.comentario.app/en/configuration/backend/static/).";
        type = types.submoduleWith {
          modules = [
            ({
              config,
              lib,
              ...
            }: {
              freeformType = with lib.types; attrsOf str;
              options = with lib; {
                HOST = mkOption {
                  type = types.str;
                  default = "localhost";
                  description = "Address on which to listen.";
                };
                PORT = mkOption {
                  type = types.port;
                  default = 8080;
                  description = "Port on which to listen.";
                };
                BASE_URL = mkOption {
                  type = types.str;
                  # TODO :: Generate default value from virtualHost.domain if present
                  default = "http://localhost:${toString config.port}";
                };
                SECRETS_FILE = mkOption {
                  type = types.str;
                  default = "secrets.yaml";
                  description = "[Secret configuration data](https://docs.comentario.app/en/configuration/backend/secrets/).";
                };
                STATIC_PATH = mkOption {
                  type = types.str;
                };
                DB_MIGRATION_PATH = mkOption {
                  type = types.str;
                };
                TEMPLATE_PATH = mkOption {
                  type = types.str;
                };
              };
            })
          ];
        };
        default = {};
      };
      settingsFile = mkOption {
        type = types.path;
        readOnly = true;
        default = pkgs.writeText "comentario.cfg" (std.concatStringsSep "\n" (map (key: "${key}=${lib.escapeShellArg (toString com.settings.${key})}") (attrNames com.settings)));
        description = "The environment file generated from `config.services.comentario.settings`.";
      };
      virtualHost = {
        domain = mkOption {
          type = types.str;
          description = "The domain of the virtualhost through which the Comentario service is proxied.";
          example = "comments.website.example";
        };
        nginx = {
          enable = mkEnableOption "Nginx VHost for Comentario";
        };
      };
    };
  };
  config = lib.mkIf com.enable (lib.mkMerge [
    {
      users.users.${com.user} = {
        isSystemUser = true;
        group = com.group;
      };
      users.groups.${com.group} = {};

      services.comentario.settings = {
        STATIC_PATH = toString com.package.frontend;
        DB_MIGRATION_PATH = "${com.package.backend}/lib/comentario/db";
        TEMPLATE_PATH = "${com.package.backend}/lib/comentario/templates";
      };

      # adapted from https://gitlab.com/comentario/comentario/-/blob/dev/resources/systemd/system/comentario.service?ref_type=heads
      systemd.services."comentario" = {
        path = [com.package.backend];
        description = "comentario";
        after = ["network.target"];
        wantedBy = ["multi-user.target"];
        serviceConfig = {
          Type = "simple";
          EnvironmentFile = com.settingsFile;
          ExecStart = "${com.package.backend}/bin/comentario -v --socket-path=\"$RUNTIME_DIRECTORY/comentario.sock\"";
          User = com.user;
          Group = com.group;
          StateDirectory = com.user;
          StateDirectoryMode = "0750";
          ConfigurationDirectory = com.user;
          ConfigurationDirectoryMode = "0750";
          RuntimeDirectory = com.user;
          RuntimeDirectoryMode = "0750";
          WorkingDirectory = com.dir.state;
          # Hardening
          UMask = "0077";
          PrivateTmp = true;
          PrivateUsers = true;
          ProtectHome = true;
          ProtectProc = true;
          ProtectSystem = true;
          PrivateMounts = true;
          PrivateDevices = true;
          ProtectClock = true;
          ProtectHostname = true;
          ProtectKernelModules = true;
          ProtectControlGroups = true;
          ProtectKernelLogs = true;
          RestrictRealtime = true;
          RestrictAddressFamilies = ["AF_INET" "AF_INET6" "AF_UNIX"];
          MemoryDenyWriteExecute = true;
          NoNewPrivileges = true;
          # TODO :: RootDirectory
          # TODO :: CapbalitiyBoundingSet
        };
      };
    }

    (lib.mkIf com.virtualHost.nginx.enable {
      services.nginx.virtualHosts.${com.virtualHost.domain} = let
        # TODO :: use unix socket instead
        proxyPass = "http://127.0.0.1:${toString com.settings.PORT}";
      in {
        locations."/" = {
          inherit proxyPass;
          recommendedProxySettings = true;
        };
        # this is necessary for live comment section updates
        locations."/ws" = {
          inherit proxyPass;
          proxyWebsockets = true;
          recommendedProxySettings = true;
        };
      };
    })
  ]);
}
