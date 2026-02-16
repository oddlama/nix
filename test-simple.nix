let
  nixpkgsPath = ./nixpkgs;
  lib = import (nixpkgsPath + "/lib");
  
  # Simple module system test
  minimalSystem = lib.evalModules {
    modules = [
      ({ config, lib, ... }: {
        options.a = lib.mkOption { type = lib.types.int; };
        options.b = lib.mkOption { type = lib.types.int; };
        config.a = 1;
        config.b = config.a + 1;  # b depends on a
      })
    ];
  };
  
  config = minimalSystem.config;
  scopeId = builtins.trackAttrset config;
  
  # Track b
  bValue = builtins.getAttrTagged scopeId ["b"] config;
  
  deps = builtins.getDependencies scopeId;
in {
  a = config.a;
  b = bValue;
  inherit deps scopeId;
}
