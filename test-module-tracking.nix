# Test dependency tracking with the NixOS module system
let
  lib = import ./nixpkgs/lib;

  # Define a simple module system with tracked dependencies
  result = lib.evalModules {
    trackDependencies = true;
    modules = [
      {
        options = {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = false;
          };
          name = lib.mkOption {
            type = lib.types.str;
            default = "default";
          };
          greeting = lib.mkOption {
            type = lib.types.str;
            default = "";
          };
          computed = lib.mkOption {
            type = lib.types.str;
            default = "";
          };
        };
      }
      # Module that creates dependencies
      ({ config, ... }: {
        config = {
          enable = true;
          name = "test";
          # greeting depends on name
          greeting = "Hello, ${config.name}!";
          # computed depends on enable and greeting
          computed = if config.enable then config.greeting else "disabled";
        };
      })
    ];
  };

  # Evaluate config values to trigger dependency recording
  values = {
    name = result.config.name;
    greeting = result.config.greeting;
    computed = result.config.computed;
  };

  # Get dependencies AFTER forcing the values
  deps = builtins.seq values result._dependencyTracking.getDependencies;

in {
  inherit (values) name greeting computed;
  inherit deps;
}
