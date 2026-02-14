# Test: Integrating dependency tracking with NixOS module system
#
# This file demonstrates how to track option dependencies in NixOS configs
# using the new trackDependencies parameter added to evalModules.
#
# IMPORTANT: Due to Nix's lazy evaluation and memoization, dependency tracking
# results depend on evaluation order. Within a single `nix eval` command,
# forcing a config value caches it, affecting subsequent tracking calls.
#
# For accurate complete dependency tracking of multiple options, run
# separate `nix eval` commands for each option:
#
#   nix develop --command ./build/src/nix/nix eval -f test-nixos-tracking.nix nginxDeps --impure
#   nix develop --command ./build/src/nix/nix eval -f test-nixos-tracking.nix postgresDeps --impure
#   nix develop --command ./build/src/nix/nix eval -f test-nixos-tracking.nix firewallDeps --impure
#
# Each of these will show the complete dependencies for that specific option.

let
  nixpkgsPath = ./nixpkgs;
  lib = import (nixpkgsPath + "/lib");

  # Create system with tracking enabled
  system = lib.evalModules {
    trackDependencies = true;
    modules = [
      # Options module
      ({ lib, ... }: {
        options = {
          services.webapp.enable = lib.mkEnableOption "webapp";
          services.webapp.port = lib.mkOption {
            type = lib.types.int;
            default = 8080;
          };
          services.nginx.enable = lib.mkEnableOption "nginx";
          services.postgresql.enable = lib.mkEnableOption "postgresql";
          services.postgresql.port = lib.mkOption {
            type = lib.types.int;
            default = 5432;
          };
          networking.firewall.allowedTCPPorts = lib.mkOption {
            type = lib.types.listOf lib.types.int;
            default = [];
          };
        };
      })

      # Config with dependencies
      ({ config, lib, ... }: {
        config = {
          services.webapp.enable = true;
          services.webapp.port = 3000;

          # nginx.enable depends on webapp.enable
          services.nginx.enable = config.services.webapp.enable;

          # postgresql.enable depends on webapp.enable
          services.postgresql.enable = config.services.webapp.enable;

          # firewall depends on many things
          networking.firewall.allowedTCPPorts =
            lib.optional config.services.nginx.enable 80
            ++ lib.optional config.services.nginx.enable 443
            ++ lib.optional config.services.postgresql.enable config.services.postgresql.port
            ++ [ config.services.webapp.port ];
        };
      })
    ];
  };

  # Helper to format dependencies nicely
  formatDeps = tracked:
    let
      deps = lib.unique (map (d: builtins.concatStringsSep "." d.accessed) tracked.dependencies);
    in {
      value = tracked.value;
      dependsOn = deps;
    };

in {
  # === Individual dependency tracking ===
  # Run each of these in a SEPARATE `nix eval` command for accurate results

  # Track nginx.enable - depends on webapp.enable
  # Run: nix develop --command ./build/src/nix/nix eval -f test-nixos-tracking.nix nginxDeps --impure
  nginxDeps = formatDeps (system._dependencyTracking.getOptionDependencies ["services" "nginx" "enable"]);
  # Expected: { value = true; dependsOn = [ "services.webapp.enable" ]; }

  # Track postgresql.enable - depends on webapp.enable
  # Run: nix develop --command ./build/src/nix/nix eval -f test-nixos-tracking.nix postgresDeps --impure
  postgresDeps = formatDeps (system._dependencyTracking.getOptionDependencies ["services" "postgresql" "enable"]);
  # Expected: { value = true; dependsOn = [ "services.webapp.enable" ]; }

  # Track firewall ports - depends on many things
  # Run: nix develop --command ./build/src/nix/nix eval -f test-nixos-tracking.nix firewallDeps --impure
  firewallDeps = formatDeps (system._dependencyTracking.getOptionDependencies ["networking" "firewall" "allowedTCPPorts"]);
  # Expected: { value = [ 80 443 5432 3000 ];
  #             dependsOn = [ "services.nginx.enable" "services.webapp.enable"
  #                           "services.postgresql.enable" "services.postgresql.port"
  #                           "services.webapp.port" ]; }

  # === Config values ===
  config = {
    webapp = {
      enable = system.config.services.webapp.enable;
      port = system.config.services.webapp.port;
    };
    nginx.enable = system.config.services.nginx.enable;
    postgresql = {
      enable = system.config.services.postgresql.enable;
      port = system.config.services.postgresql.port;
    };
    firewall.ports = system.config.networking.firewall.allowedTCPPorts;
  };

  # === Demo: What happens when multiple options are tracked together ===
  # When evaluated together, only the first accessor of webapp.enable sees the dependency
  combinedTracking = {
    first = formatDeps (system._dependencyTracking.getOptionDependencies ["services" "nginx" "enable"]);
    # After nginx forces webapp.enable, postgres won't see it as a new dependency
    second = formatDeps (system._dependencyTracking.getOptionDependencies ["services" "postgresql" "enable"]);
    # Note: second.dependsOn may be empty due to caching - this is expected behavior
  };
}
