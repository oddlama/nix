let
  nixpkgsPath = ./nixpkgs;
  lib = import (nixpkgsPath + "/lib");

  minimalSystem = lib.evalModules {
    trackDependencies = true;
    modules = [
      ({ config, lib, ... }: {
        options.base = lib.mkOption { type = lib.types.int; default = 10; };
        options.derived = lib.mkOption { type = lib.types.int; };
        # Capture the config object
        options.theConfig = lib.mkOption { 
          type = lib.types.unspecified;
          default = config;
        };
        config.derived = config.base * 2;
      })
    ];
  };

  rawConfig = minimalSystem._dependencyTracking.rawConfig;
  moduleConfig = rawConfig.theConfig;
  
  # Track the CONFIG THAT MODULES USE
  scopeId = builtins.trackAttrset moduleConfig;
  derivedValue = builtins.getAttrTagged scopeId ["derived"] moduleConfig;
  deps = builtins.getDependencies scopeId;
  
in {
  inherit scopeId derivedValue deps;
  base = moduleConfig.base;
  rawBase = rawConfig.base;
  # Check if they're the same
  sameAttrNames = builtins.attrNames rawConfig == builtins.attrNames moduleConfig;
}
