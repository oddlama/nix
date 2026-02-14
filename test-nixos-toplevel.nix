# Test: Track dependencies of a real NixOS system.build.toplevel
#
# This creates a minimal NixOS system and tracks what config options
# are accessed when evaluating system.build.toplevel.
#
# Run:
#   nix develop --command ./build/src/nix/nix eval -f test-nixos-toplevel.nix json --impure > toplevel-deps.json
#   nix develop --command ./build/src/nix/nix eval -f test-nixos-toplevel.nix graphviz --impure --raw > toplevel-deps.dot
#
# Then visualize with:
#   dot -Tsvg toplevel-deps.dot -o toplevel-deps.svg

let
  nixpkgsPath = ./nixpkgs;
  lib = import (nixpkgsPath + "/lib");

  # Base NixOS modules
  baseModules = import (nixpkgsPath + "/nixos/modules/module-list.nix");

  # Create a minimal NixOS system with tracking enabled
  minimalSystem = lib.evalModules {
    trackDependencies = true;
    specialArgs = {
      modulesPath = nixpkgsPath + "/nixos/modules";
    };
    modules = baseModules ++ [
      # Minimal configuration - only what's required
      ({ config, lib, pkgs, modulesPath, ... }: {
        # Required: boot loader
        boot.loader.grub.device = "nodev";

        # Required: root filesystem
        fileSystems."/" = {
          device = "/dev/sda1";
          fsType = "ext4";
        };

        # Set system to avoid evaluation errors
        nixpkgs.hostPlatform = "x86_64-linux";

        # State version
        system.stateVersion = "24.05";

        # Disable documentation to speed up
        documentation.enable = false;

        # Disable stuff we don't need
        networking.useDHCP = false;
        services.udisks2.enable = false;
      })
    ];
  };

  # Track a specific config path
  trackPath = path:
    minimalSystem._dependencyTracking.getOptionDependencies path;

  # Format dependencies for JSON output
  formatForJson = tracked:
    let
      deps = map (d: {
        accessor = builtins.concatStringsSep "." d.accessor;
        accessed = builtins.concatStringsSep "." d.accessed;
      }) tracked.dependencies;

      # Filter out self-references
      filteredDeps = builtins.filter (d: d.accessor != d.accessed) deps;

      # Group by accessor
      grouped = lib.groupBy (d: d.accessor) filteredDeps;

      # Create summary
      summary = lib.mapAttrs (accessor: accessedList:
        lib.unique (map (d: d.accessed) accessedList)
      ) grouped;
    in {
      totalDependencies = builtins.length filteredDeps;
      uniqueAccessors = builtins.length (builtins.attrNames grouped);
      dependenciesByAccessor = summary;
    };

  # Generate graphviz DOT format
  generateGraphviz = tracked:
    let
      deps = tracked.dependencies;

      # Create edges, filtering out self-references
      edges = lib.unique (
        builtins.filter (e: e != null) (
          map (d:
            let
              from = builtins.concatStringsSep "." d.accessor;
              to = builtins.concatStringsSep "." d.accessed;
            in
            if from != to then
              "  \"${from}\" -> \"${to}\";"
            else
              null
          ) deps
        )
      );

      # Get all unique nodes
      allNodes = lib.unique (
        (map (d: builtins.concatStringsSep "." d.accessor) deps)
        ++ (map (d: builtins.concatStringsSep "." d.accessed) deps)
      );

      # Categorize nodes by prefix for coloring
      getCategory = node:
        let
          parts = lib.splitString "." node;
          prefix = if builtins.length parts > 0 then builtins.head parts else "other";
        in prefix;

      nodesByCategory = lib.groupBy getCategory allNodes;

      # Generate node definitions with colors
      categoryColors = {
        system = "lightblue";
        boot = "lightgreen";
        services = "lightyellow";
        networking = "lightpink";
        fileSystems = "lightgray";
        users = "lightsalmon";
        environment = "lightcyan";
        nixpkgs = "lavender";
        security = "mistyrose";
        systemd = "honeydew";
      };

      nodeDefinitions = lib.concatLists (
        lib.mapAttrsToList (category: nodes:
          let
            color = categoryColors.${category} or "white";
          in
          map (node: "  \"${node}\" [fillcolor=\"${color}\", style=filled];") nodes
        ) nodesByCategory
      );

    in
    ''
      digraph NixOSToplevel {
        rankdir=LR;
        node [shape=box, fontsize=10];
        edge [fontsize=8];

        // Legend
        subgraph cluster_legend {
          label="Legend";
          fontsize=12;
          "system.*" [fillcolor="lightblue", style=filled];
          "boot.*" [fillcolor="lightgreen", style=filled];
          "services.*" [fillcolor="lightyellow", style=filled];
          "networking.*" [fillcolor="lightpink", style=filled];
        }

        // Node definitions
      ${builtins.concatStringsSep "\n" nodeDefinitions}

        // Edges
      ${builtins.concatStringsSep "\n" edges}
      }
    '';

  # Track system.build.toplevel dependencies
  toplevelTracked = trackPath ["system" "build" "toplevel"];

in {
  # JSON output with dependency information
  json = builtins.toJSON (formatForJson toplevelTracked);

  # Graphviz DOT format
  graphviz = generateGraphviz toplevelTracked;

  # Summary statistics
  summary = {
    totalDependencies = builtins.length (
      builtins.filter (d:
        builtins.concatStringsSep "." d.accessor != builtins.concatStringsSep "." d.accessed
      ) toplevelTracked.dependencies
    );
  };

  # Config values for verification
  config = {
    grubDevice = minimalSystem.config.boot.loader.grub.device;
    rootFs = minimalSystem.config.fileSystems."/".device;
    system = minimalSystem.config.nixpkgs.hostPlatform.system;
  };
}
