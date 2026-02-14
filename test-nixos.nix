# Test file: Demonstrating withDependencyTracking for NixOS-like patterns
#
# CURRENT STATUS:
# - builtins.withDependencyTracking works for lazy self-referential attrsets
# - The NixOS module system pre-evaluates options in evalModules, so by the
#   time we access config.*, values are already computed (not thunks)
# - To track NixOS module dependencies, we'd need to integrate tracking
#   into lib/modules.nix evalOptionValue function
#
# This file demonstrates:
# 1. Working: Tracking with lazy self-referential configs (like NixOS but simpler)
# 2. Integration path: How to hook into the real module system
#
# Run with: ./build/src/nix/nix eval -f test-nixos.nix --impure

let
  nixpkgsPath = ./nixpkgs;
  lib = import (nixpkgsPath + "/lib");

  #############################################################################
  # PART 1: Working example with lazy self-referential config
  # This mimics the NixOS pattern but without the module system overhead
  #############################################################################

  # A "config" that uses lazy self-reference like NixOS
  lazyConfig = {
    services.openssh.enable = true;
    services.openssh.port = 22;

    services.nginx.enable = lazyConfig.services.webapp.enable;
    services.nginx.virtualHosts."default".root = lazyConfig.services.webapp.webRoot;

    services.webapp.enable = true;
    services.webapp.webRoot = "/var/www";
    services.webapp.database.port = lazyConfig.services.postgresql.port;

    services.postgresql.enable = lazyConfig.services.webapp.enable;
    services.postgresql.port = 5432;

    networking.firewall.enable = lazyConfig.services.openssh.enable;
    networking.firewall.allowedTCPPorts =
      (if lazyConfig.services.openssh.enable then [ lazyConfig.services.openssh.port ] else [])
      ++ (if lazyConfig.services.nginx.enable then [ 80 443 ] else []);

    users.users.admin.extraGroups =
      [ "wheel" ]
      ++ lib.optional lazyConfig.services.nginx.enable "nginx"
      ++ lib.optional lazyConfig.services.postgresql.enable "postgres";
  };

  # Track a specific option's dependencies
  trackLazy = path:
    let
      result = builtins.withDependencyTracking path lazyConfig (lib.attrByPath path null lazyConfig);
      # Filter self-references
      filtered = builtins.filter (d: d.accessor != d.accessed) result.dependencies;
    in result // { dependencies = filtered; };

  # Build dependency tree from multiple paths
  buildDependencyTree = paths:
    let
      allDeps = builtins.concatLists (map (p: (trackLazy p).dependencies) paths);
      # Group by accessor
      byAccessor = lib.groupBy (d: builtins.concatStringsSep "." d.accessor) allDeps;
    in lib.mapAttrs (k: deps:
      lib.unique (map (d: builtins.concatStringsSep "." d.accessed) deps)
    ) byAccessor;

  trackedPaths = [
    ["services" "nginx" "enable"]
    ["services" "postgresql" "enable"]
    ["services" "webapp" "database" "port"]
    ["networking" "firewall" "enable"]
    ["networking" "firewall" "allowedTCPPorts"]
    ["users" "users" "admin" "extraGroups"]
  ];

  #############################################################################
  # PART 2: Real NixOS module system (for comparison)
  # Note: Dependencies are NOT tracked because options are pre-evaluated
  #############################################################################

  nixosSystem = import (nixpkgsPath + "/nixos/lib/eval-config.nix") {
    inherit lib;
    system = "x86_64-linux";
    modules = [
      ({ config, lib, ... }: {
        config = {
          boot.loader.grub.device = "nodev";
          fileSystems."/" = { device = "/dev/sda1"; fsType = "ext4"; };
          services.openssh.enable = true;
          services.nginx.enable = config.services.openssh.enable;
          documentation.enable = false;
        };
      })
    ];
  };

in {
  # === WORKING: Lazy config tracking ===

  # Track individual options
  lazyTracking = {
    nginxEnable = trackLazy ["services" "nginx" "enable"];
    postgresEnable = trackLazy ["services" "postgresql" "enable"];
    firewallPorts = trackLazy ["networking" "firewall" "allowedTCPPorts"];
    adminGroups = trackLazy ["users" "users" "admin" "extraGroups"];
  };

  # Full dependency tree
  dependencyTree = buildDependencyTree trackedPaths;

  # Graphviz output
  graphviz = let
    deps = builtins.concatLists (map (p: (trackLazy p).dependencies) trackedPaths);
    edges = lib.unique (map (d:
      "  \"${builtins.concatStringsSep "." d.accessor}\" -> \"${builtins.concatStringsSep "." d.accessed}\";"
    ) deps);
  in ''
    digraph NixOSConfig {
      rankdir=LR;
      node [shape=box];
    ${builtins.concatStringsSep "\n" edges}
    }
  '';

  # === NOT WORKING YET: Real NixOS module system ===
  # These show empty dependencies because options are pre-evaluated

  nixosTracking = {
    # By the time we access these, they're already evaluated to `true`
    nginxEnable = builtins.withDependencyTracking
      ["services" "nginx" "enable"]
      nixosSystem.config
      nixosSystem.config.services.nginx.enable;
  };

  # Values are correct, just no dependency tracking
  nixosValues = {
    sshEnable = nixosSystem.config.services.openssh.enable;
    nginxEnable = nixosSystem.config.services.nginx.enable;
  };

  # === NEXT STEPS ===
  # To track real NixOS module dependencies, we need to:
  # 1. Modify lib/modules.nix evalOptionValue to use withDependencyTracking
  # 2. Or create a wrapper that intercepts option evaluation
  # 3. Store dependencies per-option during module evaluation
}
