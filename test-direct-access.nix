let
  nixpkgsPath = ./nixpkgs;
  lib = import (nixpkgsPath + "/lib");

  minimalSystem = lib.evalModules {
    trackDependencies = true;
    modules = [
      ({ config, lib, ... }: {
        options.base = lib.mkOption { type = lib.types.int; default = 10; };
        options.derived = lib.mkOption { type = lib.types.int; };
        # derived accesses base
        config.derived = config.base * 2;
      })
    ];
  };

  rawConfig = minimalSystem._dependencyTracking.rawConfig;
  scopeId = builtins.trackAttrset rawConfig;

  # Push a manual force context and then access rawConfig.base
  # This tests if the tracking is working at all for rawConfig
  test = 
    let
      # Manually push force context for "test" 
      ctx = builtins.getAttrTagged scopeId ["test"] { test = rawConfig.base; };
    in ctx;

  deps = builtins.getDependencies scopeId;
  
in {
  inherit test deps;
  derivedValue = builtins.getAttrTagged scopeId ["derived"] rawConfig;
  deps2 = builtins.getDependencies scopeId;
}
