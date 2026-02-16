let
  nixpkgsPath = ./nixpkgs;
  lib = import (nixpkgsPath + "/lib");

  minimalSystem = lib.evalModules {
    trackDependencies = true;
    modules = [
      ({ config, lib, ... }: {
        options.base = lib.mkOption { type = lib.types.int; default = 10; };
        options.derived = lib.mkOption { type = lib.types.int; };
        # Capture the config object itself
        options.capturedConfig = lib.mkOption {
          type = lib.types.unspecified;
          default = config;
        };
        config.derived = config.base * 2;
      })
    ];
  };

  rawConfig = minimalSystem._dependencyTracking.rawConfig;
  capturedConfig = rawConfig.capturedConfig;
  
  # Check attr names
  rawNames = builtins.attrNames rawConfig;
  capturedNames = builtins.attrNames capturedConfig;
  
in rec {
  # Are base values equal?
  rawBase = rawConfig.base;
  capturedBase = capturedConfig.base;
  baseEqual = rawConfig.base == capturedConfig.base;
  
  # Are attr names equal?
  inherit rawNames capturedNames;
  namesEqual = rawNames == capturedNames;
  
  # Test tracking on captured config (the one modules actually use)
  trackingOnCaptured = 
    let
      scopeId = builtins.trackAttrset capturedConfig;
      value = builtins.getAttrTagged scopeId ["derived"] capturedConfig;
      deps = builtins.getDependencies scopeId;
    in {
      inherit scopeId value deps;
    };
    
  # Test tracking on rawConfig
  trackingOnRaw = 
    let
      scopeId = builtins.trackAttrset rawConfig;
      value = builtins.getAttrTagged scopeId ["derived"] rawConfig;
      deps = builtins.getDependencies scopeId;
    in {
      inherit scopeId value deps;
    };
}
