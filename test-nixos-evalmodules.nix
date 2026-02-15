let
  nixpkgsPath = ./nixpkgs;
  lib = import (nixpkgsPath + "/lib");

  inherit (lib)
    mkOption
    mkIf
    mkDefault
    mkMerge
    types
    ;

  # Create a minimal module system with tracking enabled
  # This gives us access to rawConfig via _dependencyTracking
  minimalSystem = lib.evalModules {
    trackDependencies = true;
    modules = [

      # ============================================================
      # MODULE 1: User definitions
      # ============================================================
      (
        { config, lib, ... }:
        {
          options.users = mkOption {
            type = types.attrsOf (
              types.submodule (
                { name, ... }:
                {
                  options = {
                    isAdmin = mkOption {
                      type = types.bool;
                      default = false;
                    };

                    enabledServices = mkOption {
                      type = types.listOf types.str;
                      default = [ ];
                    };
                  };
                }
              )
            );
            default = { };
          };
        }
      )

      # ============================================================
      # MODULE 2: Service definitions (nested submodules!)
      # ============================================================
      (
        { config, lib, ... }:
        {
          options.services = mkOption {
            type = types.attrsOf (
              types.submodule (
                { name, ... }:
                {
                  options = {
                    enable = mkOption {
                      type = types.bool;
                      default = true;
                    };

                    requiredAdmin = mkOption {
                      type = types.bool;
                      default = false;
                    };

                    metadata = mkOption {
                      type = types.submodule {
                        options = {
                          ports = mkOption {
                            type = types.listOf types.int;
                            default = [ ];
                          };

                          description = mkOption {
                            type = types.str;
                            default = "No description";
                          };
                        };
                      };
                    };
                  };
                }
              )
            );
            default = { };
          };
        }
      )

      # ============================================================
      # MODULE 3: Cross-reference users + services
      # Auto-enable services for admins
      # ============================================================
      (
        { config, lib, ... }:

        let
          inherit (lib) mapAttrs filterAttrs attrNames;

          adminServices = attrNames (filterAttrs (_: svc: svc.requiredAdmin) config.services);

        in
        {
          config.users = mapAttrs (
            _: user:
            mkIf user.isAdmin {
              enabledServices = mkMerge [
                (mkDefault user.enabledServices)
                adminServices
              ];
            }
          ) config.users;
        }
      )

      # ============================================================
      # MODULE 4: Derived outputs
      # ============================================================
      (
        { config, lib, ... }:
        {
          options.activeServices = mkOption {
            type = types.listOf types.str;
            description = "List of active service names";
          };

          options.serviceCount = mkOption {
            type = types.int;
            description = "Number of services";
          };

          # activeServices depends on services
          config.activeServices = lib.attrNames (lib.filterAttrs (_: s: s.enable) config.services);

          # serviceCount depends on activeServices
          config.serviceCount = lib.length config.activeServices;
        }
      )

      # ============================================================
      # MODULE 5: Concrete configuration
      # ============================================================
      {
        config = {

          users = {
            alice = {
              isAdmin = true;
            };

            bob = {
              isAdmin = false;
              enabledServices = [ "web" ];
            };
          };

          services = {
            web = {
              metadata.description = "Web server";
              metadata.ports = [
                80
                443
              ];
            };

            database = {
              requiredAdmin = true;
              metadata.ports = [ 5432 ];
            };
          };
        };
      }

    ];
  };

  # ============================================================
  # NEW APPROACH: Using thunk-embedded origins
  # ============================================================

  # Use rawConfig to get the same Bindings* that modules access internally.
  # Note: trackDependencies=true enables the OLD tracking approach which uses
  # valueOrigins. This can interfere with our new thunk-embedded origins approach.
  # For now, we accept this limitation - the dependencies may include some
  # duplicates or incorrect attributions from the old approach.
  config = minimalSystem._dependencyTracking.rawConfig;

  # Register config for tracking - returns a scope ID
  scopeId = builtins.trackAttrset config;

  # Helper to tag and track a specific path
  # This tags the thunk at 'path' with its origin, then forces it
  trackPath = path:
    let
      # getAttrTagged: get attribute at path and tag it with that path as origin
      # When forced, any accesses to config.* will be recorded with accessor=path
      taggedValue = builtins.getAttrTagged scopeId path config;

      # CRITICAL: Force the value BEFORE getting dependencies!
      # Due to lazy evaluation, dependencies are only recorded when values are forced.
      # We use seq to create a dependency chain: force taggedValue, then get deps.
      allDeps = builtins.seq (builtins.deepSeq taggedValue null) (builtins.getDependencies scopeId);

      # Filter to only deps from this accessor
      pathStr = builtins.concatStringsSep "." path;
      myDeps = builtins.filter (d:
        builtins.concatStringsSep "." d.accessor == pathStr
      ) allDeps;
    in {
      value = taggedValue;
      dependencies = myDeps;
    };

  # Format dependencies for JSON output
  formatForJson =
    tracked:
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
      summary = lib.mapAttrs (
        accessor: accessedList: lib.unique (map (d: d.accessed) accessedList)
      ) grouped;
    in
    {
      totalDependencies = builtins.length filteredDeps;
      uniqueAccessors = builtins.length (builtins.attrNames grouped);
      dependenciesByAccessor = summary;
    };

  # Generate graphviz DOT format
  generateGraphviz =
    tracked:
    let
      deps = tracked.dependencies;

      # Create edges, filtering out self-references
      edges = lib.unique (
        builtins.filter (e: e != null) (
          map (
            d:
            let
              from = builtins.concatStringsSep "." d.accessor;
              to = builtins.concatStringsSep "." d.accessed;
            in
            if from != to then "  \"${from}\" -> \"${to}\";" else null
          ) deps
        )
      );

      # Get all unique nodes
      allNodes = lib.unique (
        (map (d: builtins.concatStringsSep "." d.accessor) deps)
        ++ (map (d: builtins.concatStringsSep "." d.accessed) deps)
      );

      # Categorize nodes by prefix for coloring
      getCategory =
        node:
        let
          parts = lib.splitString "." node;
          prefix = if builtins.length parts > 0 then builtins.head parts else "other";
        in
        prefix;

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
        lib.mapAttrsToList (
          category: nodes:
          let
            color = categoryColors.${category} or "white";
          in
          map (node: "  \"${node}\" [fillcolor=\"${color}\", style=filled];") nodes
        ) nodesByCategory
      );

    in
    ''
      digraph moduledeps {
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

  # Track various paths
  servicesTracked = trackPath [ "services" ];
  activeServicesTracked = trackPath [ "activeServices" ];
  serviceCountTracked = trackPath [ "serviceCount" ];

  # Get ALL dependencies from the scope (after forcing all tracked values)
  allDependencies =
    builtins.seq servicesTracked.value
    (builtins.seq activeServicesTracked.value
    (builtins.seq serviceCountTracked.value
    (builtins.getDependencies scopeId)));

in
{
  # JSON output with dependency information
  json = builtins.toJSON (formatForJson activeServicesTracked);

  # Graphviz DOT format
  graphviz = generateGraphviz activeServicesTracked;

  # Summary statistics
  summary = {
    totalDependencies = builtins.length (
      builtins.filter (
        d: builtins.concatStringsSep "." d.accessor != builtins.concatStringsSep "." d.accessed
      ) allDependencies
    );
  };

  # New approach outputs - demonstrate the raw API
  newApproach = {
    # The scope ID used for tracking
    inherit scopeId;

    # Raw dependencies list from getDependencies
    rawDependencies = allDependencies;

    # Dependencies by path
    byPath = {
      services = servicesTracked.dependencies;
      activeServices = activeServicesTracked.dependencies;
      serviceCount = serviceCountTracked.dependencies;
    };

    # The actual values (to verify they're correct)
    values = {
      services = servicesTracked.value;
      activeServices = activeServicesTracked.value;
      serviceCount = serviceCountTracked.value;
    };
  };

  # Direct test of the thunk-embedded origins approach
  # This demonstrates the API without module system complexity
  directTest = let
    # Simple fixpoint with explicit self references
    testConfig = let self = {
      a = 1;
      b = self.a + 1;
      c = self.b + self.a;
    }; in self;

    testScopeId = builtins.trackAttrset testConfig;
    bValue = builtins.getAttrTagged testScopeId ["b"] testConfig;
    cValue = builtins.getAttrTagged testScopeId ["c"] testConfig;

    # CRITICAL: Force values BEFORE getting dependencies (lazy evaluation!)
    testDeps = builtins.seq bValue (builtins.seq cValue (builtins.getDependencies testScopeId));
  in {
    scopeId = testScopeId;
    values = { inherit (testConfig) a; b = bValue; c = cValue; };
    dependencies = testDeps;
    # Expected: b depends on a, c depends on a and b
  };
}
