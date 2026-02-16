# Simplified NixOS-like structure to debug tracking granularity issues
let
  lib = import ./nixpkgs/lib;

  result = lib.evalModules {
    trackDependencies = true;
    modules = [
      # Option declarations mirroring NixOS structure
      {
        options = {
          services.nginx.enable = lib.mkOption {
            type = lib.types.bool;
            default = false;
          };
          services.nginx.package = lib.mkOption {
            type = lib.types.str;
            default = "nginx";
          };
          services.webapp.enable = lib.mkOption {
            type = lib.types.bool;
            default = false;
          };

          environment.etc = lib.mkOption {
            type = lib.types.attrsOf lib.types.str;
            default = {};
          };

          systemd.services = lib.mkOption {
            type = lib.types.attrsOf lib.types.str;
            default = {};
          };

          system.build = lib.mkOption {
            type = lib.types.attrsOf lib.types.str;
            default = {};
          };
        };
      }

      # Module: webapp
      ({ config, ... }: {
        config.services.webapp.enable = true;
      })

      # Module: nginx (depends on webapp) -- uses "let cfg" pattern like real NixOS!
      ({ config, lib, ... }: {
        config = lib.mkIf config.services.webapp.enable {
          services.nginx.enable = true;
        };
      })

      # Module A: direct access pattern (works)
      ({ config, lib, ... }: {
        config.systemd.services = lib.mkIf config.services.nginx.enable {
          nginx = "ExecStart=${config.services.nginx.package}";
        };
      })

      # Module B: "let cfg" pattern (the NixOS idiom that may break tracking)
      ({ config, lib, ... }: let
        cfg = config.services.nginx;  # <-- split select chain!
      in {
        config.environment.etc."nginx-status" =
          "enabled: ${lib.boolToString cfg.enable}, pkg: ${cfg.package}";
      })

      # Module: system.build.toplevel
      ({ config, lib, ... }: {
        config.system.build.toplevel =
          "etc: ${config.environment.etc."nginx-status"}, svc: ${config.systemd.services.nginx or "none"}";
      })
    ];
  };

  toplevel = result.config.system.build.toplevel;
  deps = builtins.seq toplevel result._dependencyTracking.getDependencies;

  pathToStr = lib.concatStringsSep ".";

in {
  inherit toplevel;
  depCount = builtins.length deps;
  depsSummary = map (d: "${pathToStr d.accessor} -> ${pathToStr d.accessed}") deps;
}
