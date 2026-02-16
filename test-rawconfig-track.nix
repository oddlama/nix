let
  nixpkgsPath = ./nixpkgs;
  lib = import (nixpkgsPath + "/lib");
  
  minimalSystem = lib.evalModules {
    trackDependencies = true;
    modules = [
      ({ config, lib, ... }: {
        options.a = lib.mkOption { type = lib.types.int; };
        options.b = lib.mkOption { type = lib.types.int; };
        config.a = 1;
        config.b = config.a + 1;
      })
    ];
  };
  
  rawConfig = minimalSystem._dependencyTracking.rawConfig;
  scopeId = builtins.trackAttrset rawConfig;
  
  # Track b
  bValue = builtins.getAttrTagged scopeId ["b"] rawConfig;
  
  deps = builtins.getDependencies scopeId;
in {
  a = rawConfig.a;
  b = bValue;
  inherit deps scopeId;
}
