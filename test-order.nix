let
  nixpkgsPath = ./nixpkgs;
  lib = import (nixpkgsPath + "/lib");

  minimalSystem = lib.evalModules {
    trackDependencies = true;
    modules = [
      ({ config, lib, ... }: {
        options.base = lib.mkOption { type = lib.types.int; default = 10; };
        options.derived = lib.mkOption { type = lib.types.int; };
        config.derived = config.base * 2;
      })
    ];
  };

  rawConfig = minimalSystem._dependencyTracking.rawConfig;
  
  # Force capturedConfig access first to potentially affect evaluation order
  capturedConfig = rawConfig.capturedConfig or null;
  
  scopeId = builtins.trackAttrset rawConfig;
  derivedValue = builtins.getAttrTagged scopeId ["derived"] rawConfig;
  deps = builtins.getDependencies scopeId;
  
in {
  inherit scopeId derivedValue deps;
  base = rawConfig.base;
}
