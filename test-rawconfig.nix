let
  nixpkgsPath = ./nixpkgs;
  lib = import (nixpkgsPath + "/lib");
  
  minimalSystem = lib.evalModules {
    trackDependencies = true;
    modules = [
      ({ config, lib, ... }: {
        options.a = lib.mkOption { type = lib.types.int; };
        options.b = lib.mkOption { type = lib.types.int; };
        options.configNames = lib.mkOption { type = lib.types.str; };
        config.a = 1;
        config.b = config.a + 1;
        config.configNames = builtins.concatStringsSep "," (builtins.attrNames config);
      })
    ];
  };
  
  rawConfig = minimalSystem._dependencyTracking.rawConfig;
  rawNames = builtins.concatStringsSep "," (builtins.attrNames rawConfig);
  
in {
  internalNames = rawConfig.configNames;
  rawNames = rawNames;
  same = rawConfig.configNames == rawNames;
}
