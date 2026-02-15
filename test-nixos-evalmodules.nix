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
      # MODULE 4: Derived output (pure fixpoint magic)
      # ============================================================
      (
        { config, lib, ... }:
        {
          options.systemReport = mkOption {
            type = types.attrs;
            default = { };
          };

          config.systemReport = {
            # List of active services
            activeServices = lib.attrNames (lib.filterAttrs (_: s: s.enable) config.services);

            # Users and their enabled services (no self-reference)
            userServiceList = lib.mapAttrs (_: user: user.enabledServices) config.users;
          };
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

  # Track a specific config path
  trackPath = path: minimalSystem._dependencyTracking.getOptionDependencies path;

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

  reportTracked = trackPath [
    "systemReport"
  ];
in
{
  # JSON output with dependency information
  json = builtins.toJSON (formatForJson reportTracked);

  # Graphviz DOT format
  graphviz = generateGraphviz reportTracked;

  # Summary statistics
  summary = {
    totalDependencies = builtins.length (
      builtins.filter (
        d: builtins.concatStringsSep "." d.accessor != builtins.concatStringsSep "." d.accessed
      ) reportTracked.dependencies
    );
  };
}
