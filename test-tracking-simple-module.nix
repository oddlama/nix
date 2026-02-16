let
  nixpkgsPath = ./nixpkgs;
  lib = import (nixpkgsPath + "/lib");

  inherit (lib)
    mkOption
    types
    ;

  # Simple module system without circular references
  minimalSystem = lib.evalModules {
    trackDependencies = true;
    modules = [
      ({ config, lib, ... }: {
        options.base = mkOption {
          type = types.int;
          default = 10;
        };
        
        options.multiplier = mkOption {
          type = types.int;
          default = 2;
        };
        
        options.result = mkOption {
          type = types.int;
        };
        
        # result depends on base and multiplier
        config.result = config.base * config.multiplier;
      })
    ];
  };

  # Use rawConfig to get the same Bindings* that modules access
  rawConfig = minimalSystem._dependencyTracking.rawConfig;
  scopeId = builtins.trackAttrset rawConfig;

  # Track result
  resultValue = builtins.getAttrTagged scopeId ["result"] rawConfig;
  
  # Force result before getting deps
  deps = builtins.seq (builtins.deepSeq resultValue null) (builtins.getDependencies scopeId);

in {
  values = {
    base = rawConfig.base;
    multiplier = rawConfig.multiplier;
    result = resultValue;
  };
  
  dependencies = deps;
  
  # Expected: result depends on base and multiplier
}
