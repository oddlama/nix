let
  nixpkgsPath = ./nixpkgs;
  lib = import (nixpkgsPath + "/lib");

  inherit (lib)
    mkOption
    types
    ;

  minimalSystem = lib.evalModules {
    trackDependencies = true;
    modules = [
      # Module 1: Base options
      ({ config, lib, ... }: {
        options.base = mkOption {
          type = types.int;
          default = 10;
        };
        
        options.multiplier = mkOption {
          type = types.int;
          default = 2;
        };
      })

      # Module 2: Derived options that depend on base
      ({ config, lib, ... }: {
        options.derived = mkOption {
          type = types.int;
        };
        
        options.computed = mkOption {
          type = types.int;
        };
        
        # derived depends on base
        config.derived = config.base * config.multiplier;
        
        # computed depends on derived and base
        config.computed = config.derived + config.base;
      })
    ];
  };

  # Use rawConfig to get the same Bindings* that modules access
  rawConfig = minimalSystem._dependencyTracking.rawConfig;
  scopeId = builtins.trackAttrset rawConfig;

  # Track specific options
  trackOption = path:
    let
      taggedValue = builtins.getAttrTagged scopeId path rawConfig;
      allDeps = builtins.getDependencies scopeId;
      pathStr = builtins.concatStringsSep "." path;
      myDeps = builtins.filter (d:
        builtins.concatStringsSep "." d.accessor == pathStr
      ) allDeps;
    in {
      value = taggedValue;
      dependencies = myDeps;
    };

in {
  values = {
    base = rawConfig.base;
    multiplier = rawConfig.multiplier;
    derived = (trackOption ["derived"]).value;
    computed = (trackOption ["computed"]).value;
  };
  
  dependencies = {
    derived = (trackOption ["derived"]).dependencies;
    computed = (trackOption ["computed"]).dependencies;
  };
  
  allDeps = builtins.getDependencies scopeId;
}
