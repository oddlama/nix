# Minimal NixOS evaluation with dependency tracking for system.build.toplevel
#
# This is a thin test harness that uses the integrated dependency tracking
# from eval-config.nix. All processing logic lives in nixpkgs/nixos/lib/dependency-tracking.nix.
#
# Usage:
#   nix eval -f test-nixos-toplevel.nix filteredDotOutput --raw > deps.dot
#   nix eval -f test-nixos-toplevel.nix configValues --json > config.json
#   nix eval -f test-nixos-toplevel.nix counts
let
  nixpkgs = import ./nixpkgs { };
  lib = nixpkgs.lib;

  nixos = import ./nixpkgs/nixos/lib/eval-config.nix {
    inherit lib;
    trackDependencies = true;
    modules = [
      (
        { modulesPath, ... }:
        {
          imports = [
            (modulesPath + "/profiles/minimal.nix")
          ];

          boot.loader.grub.device = "nodev";
          fileSystems."/" = {
            device = "/dev/sda1";
            fsType = "ext4";
          };
          system.stateVersion = "24.05";
        }
      )
    ];
  };

  # Force toplevel evaluation first, then access tracking data
  toplevel = nixos.config.system.build.toplevel;
  tracking = builtins.seq toplevel nixos.dependencyTracking;

in
{
  inherit (tracking)
    rawDeps
    filteredDeps
    configValues
    explicitConfigValues
    leafNodes
    explicitLeafNodes
    keptNodes
    rawDotOutput
    filteredDotOutput
    counts
    ;
  toplevelPath = toString toplevel;
}
