# Test that simulates NixOS-like module structure with services
let
  lib = import ./nixpkgs/lib;

  result = lib.evalModules {
    trackDependencies = true;
    modules = [
      # Option declarations
      {
        options = {
          networking.hostName = lib.mkOption {
            type = lib.types.str;
            default = "localhost";
          };
          services.nginx.enable = lib.mkOption {
            type = lib.types.bool;
            default = false;
          };
          services.nginx.virtualHosts = lib.mkOption {
            type = lib.types.attrsOf lib.types.str;
            default = {};
          };
          services.webapp.enable = lib.mkOption {
            type = lib.types.bool;
            default = false;
          };
          services.webapp.port = lib.mkOption {
            type = lib.types.int;
            default = 8080;
          };
          system.build.toplevel = lib.mkOption {
            type = lib.types.str;
            default = "";
          };
        };
      }
      # Module that defines webapp
      ({ config, lib, ... }: {
        config = {
          services.webapp.enable = true;
          services.webapp.port = 3000;
        };
      })
      # Module that auto-configures nginx for webapp
      ({ config, lib, ... }: {
        config = lib.mkIf config.services.webapp.enable {
          services.nginx.enable = true;
          services.nginx.virtualHosts.webapp = "proxy_pass http://localhost:${toString config.services.webapp.port}";
        };
      })
      # Module that builds toplevel
      ({ config, lib, ... }: {
        config.system.build.toplevel = ''
          Host: ${config.networking.hostName}
          Nginx: ${lib.boolToString config.services.nginx.enable}
          ${lib.concatStringsSep "\n" (lib.mapAttrsToList (name: cfg: "${name}: ${cfg}") config.services.nginx.virtualHosts)}
        '';
      })
    ];
  };

  # Force evaluation of toplevel first
  toplevel = result.config.system.build.toplevel;

  # Then get dependencies (after forcing toplevel)
  deps = builtins.seq toplevel result._dependencyTracking.getDependencies;

in {
  inherit toplevel deps;
}
