let
  nixpkgsPath = ./nixpkgs;
  lib = import (nixpkgsPath + "/lib");

  minimalSystem = lib.evalModules {
    trackDependencies = true;
    modules = [
      ({ config, lib, ... }: {
        options.base = lib.mkOption { type = lib.types.int; default = 10; };
        options.derived = lib.mkOption { type = lib.types.int; };
        # Add a debug option to check config identity
        options.configCheck = lib.mkOption { 
          type = lib.types.str;
          # This will evaluate later when we access it
          default = "dummy";
        };
        config.derived = config.base * 2;
        # When configCheck is evaluated, this will run:
        config.configCheck = builtins.trace "config.base access: ${toString config.base}" "done";
      })
    ];
  };

  rawConfig = minimalSystem._dependencyTracking.rawConfig;
  
  scopeId = builtins.trackAttrset rawConfig;
  
in {
  # Force configCheck to see the trace
  check = rawConfig.configCheck;
  
  # Now track derived
  derivedValue = builtins.getAttrTagged scopeId ["derived"] rawConfig;
  deps = builtins.getDependencies scopeId;
}
