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
  
in rec {
  # Test tracking on rawConfig only
  trackingOnRaw = 
    let
      scopeId = builtins.trackAttrset rawConfig;
      value = builtins.getAttrTagged scopeId ["derived"] rawConfig;
      deps = builtins.getDependencies scopeId;
    in {
      inherit scopeId value deps;
    };
}
