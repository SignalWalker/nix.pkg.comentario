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
        default = "comentario";
      };
      group = mkOption {
        type = types.str;
        default = "comentario";
      };
      dir = {
        state = mkOption {
          type = types.str;
          readOnly = true;
          default = "/var/lib/${com.user}";
        };
        configuration = mkOption {
          type = types.str;
          readOnly = true;
          default = "/etc/${com.user}";
        };
      };
      settings = mkOption {
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
                };
                PORT = mkOption {
                  type = types.port;
                  default = 8080;
                };
                BASE_URL = mkOption {
                  type = types.str;
                  default = "http://localhost:${toString config.port}";
                };
                SECRETS_FILE = mkOption {
                  type = types.str;
                  default = "secrets.yaml";
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
      };
      virtualHost = {
        domain = mkOption {
          type = types.str;
        };
        nginx = {
          enable = mkEnableOption "Nginx VHost for Comentario";
        };
      };
    };
  };
  disabledModules = [];
  imports = [];
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
        path = [com.package.backend com.package.frontend];
        description = "comentario";
        after = ["network.target"];
        wantedBy = ["multi-user.target"];
        serviceConfig = {
          Type = "simple";
          EnvironmentFile = com.settingsFile;
          ExecStart = "${com.package.backend}/bin/comentario -v";
          User = com.user;
          Group = com.group;
          StateDirectory = com.user;
          StateDirectoryMode = "0750";
          ConfigurationDirectory = com.user;
          ConfigurationDirectoryMode = "0750";
          WorkingDirectory = com.dir.state;
        };
      };
    }

    (lib.mkIf com.virtualHost.nginx.enable {
      services.nginx.virtualHosts.${com.virtualHost.domain} = let
        proxyPass = "http://127.0.0.1:${toString com.settings.PORT}";
      in {
        locations."/" = {
          inherit proxyPass;
          recommendedProxySettings = true;
        };
        locations."/ws" = {
          inherit proxyPass;
          proxyWebsockets = true;
          recommendedProxySettings = true;
        };
      };
    })
  ]);
  meta = {};
}
