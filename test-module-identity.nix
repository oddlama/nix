let
  nixpkgsPath = ./nixpkgs;
  lib = import (nixpkgsPath + "/lib");
  
  minimalSystem = lib.evalModules {
    modules = [
      ({ config, lib, ... }: {
        options.a = lib.mkOption { type = lib.types.int; };
        options.b = lib.mkOption { type = lib.types.int; };
        options.configNames = lib.mkOption { type = lib.types.str; };
        config.a = 1;
        config.b = config.a + 1;
        # Store the config's attr names
        config.configNames = builtins.concatStringsSep "," (builtins.attrNames config);
      })
    ];
  };
  
  externalConfig = minimalSystem.config;
  externalNames = builtins.concatStringsSep "," (builtins.attrNames externalConfig);
  
in {
  internalNames = externalConfig.configNames;
  externalNames = externalNames;
  same = externalConfig.configNames == externalNames;
}
