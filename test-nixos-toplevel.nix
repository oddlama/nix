# Minimal NixOS evaluation with dependency tracking for system.build.toplevel
let
  # Import our local patched nixpkgs
  nixpkgs = import ./nixpkgs { };
  lib = nixpkgs.lib;

  # Use the patched eval-config with trackDependencies
  nixos = import ./nixpkgs/nixos/lib/eval-config.nix {
    inherit lib;
    trackDependencies = true;
    modules = [
      # Minimal config for a bootable system
      ({ config, lib, pkgs, modulesPath, ... }: {
        imports = [
          (modulesPath + "/profiles/minimal.nix")
        ];

        boot.loader.grub.device = "nodev";
        fileSystems."/" = {
          device = "/dev/sda1";
          fsType = "ext4";
        };
        system.stateVersion = "24.05";
      })
    ];
  };

  # Force toplevel evaluation first
  toplevel = nixos.config.system.build.toplevel;

  # 1. Raw deps + deduplication
  rawDeps = builtins.seq toplevel nixos._dependencyTracking.getDependencies;
  deps = let
    edgeKey = dep: builtins.toJSON [ dep.accessor dep.accessed ];
    grouped = builtins.groupBy edgeKey rawDeps;
  in map (group: builtins.head group) (builtins.attrValues grouped);

  # Convert a path list to a dot-safe node name
  pathToNode = path: builtins.replaceStrings ["."] ["_"] (lib.concatStringsSep "." path);

  # Generate DOT format for graphviz (full graph)
  dotOutput = ''
    digraph dependencies {
      rankdir=LR;
      node [shape=box, fontsize=10];
      edge [fontsize=8];

    ${lib.concatMapStringsSep "\n" (dep:
      let
        accessor = pathToNode dep.accessor;
        accessed = pathToNode dep.accessed;
      in "  \"${accessor}\" -> \"${accessed}\";"
    ) deps}
    }
  '';

  # 2. Collect option paths from nixos.options
  # Recursive walk: stop at _type = "option" nodes, use tryEval for robustness
  collectOptionPaths = let
    walk = prefix: node:
      let res = builtins.tryEval (
        if builtins.isAttrs node && (node._type or "") == "option"
        then [prefix]
        else if builtins.isAttrs node
        then lib.concatLists (lib.mapAttrsToList (name: child: walk (prefix ++ [name]) child) node)
        else []
      ); in if res.success then res.value else [];
  in walk [] nixos.options;

  # 3. Option path lookup set (tab-separated keys — attr names never contain tabs)
  pathKey = builtins.concatStringsSep "\t";
  optionPathSet = builtins.listToAttrs (map (p: { name = pathKey p; value = true; }) collectOptionPaths);

  # 4. Node filtering: kept if path or any prefix is an option
  isKeptNode = path:
    builtins.any (i: optionPathSet ? ${pathKey (lib.take i path)})
      (lib.range 1 (builtins.length path));

  # 5. Collect all unique nodes, partition into kept/pruned
  allNodes = let
    allPaths = map (dep: dep.accessor) deps ++ map (dep: dep.accessed) deps;
    grouped = builtins.groupBy pathKey allPaths;
  in map (group: builtins.head group) (builtins.attrValues grouped);

  keptNodes = builtins.filter isKeptNode allNodes;
  prunedNodes = builtins.filter (p: !(isKeptNode p)) allNodes;

  keptNodeSet = builtins.listToAttrs (map (p: { name = pathKey p; value = true; }) keptNodes);
  prunedNodeSet = builtins.listToAttrs (map (p: { name = pathKey p; value = true; }) prunedNodes);

  # Build adjacency map: accessor key -> list of accessed keys
  adjacencyMap = let
    edgesWithKeys = map (dep: {
      srcKey = pathKey dep.accessor;
      dstKey = pathKey dep.accessed;
    }) deps;
    grouped = builtins.groupBy (e: e.srcKey) edgesWithKeys;
  in builtins.mapAttrs (k: edges: map (e: e.dstKey) edges) grouped;

  # 6. Transitive edges via genericClosure
  # For each kept source, BFS through pruned intermediates to find reachable kept targets
  reachableKeptTargets = sourceKey: let
    closure = builtins.genericClosure {
      startSet = map (k: { key = k; }) (adjacencyMap.${sourceKey} or []);
      operator = item:
        if keptNodeSet ? ${item.key} then []  # stop at kept nodes
        else map (k: { key = k; }) (adjacencyMap.${item.key} or []);
    };
  in builtins.filter (item: keptNodeSet ? ${item.key} && item.key != sourceKey) closure;

  # Build filtered edges
  filteredEdges = let
    keptSourceKeys = builtins.filter (k: adjacencyMap ? ${k}) (map pathKey keptNodes);
    rawEdges = lib.concatMap (srcKey:
      map (item: { accessor = lib.splitString "\t" srcKey; accessed = lib.splitString "\t" item.key; })
        (reachableKeptTargets srcKey)
    ) keptSourceKeys;
    # Deduplicate filtered edges
    grouped = builtins.groupBy (e: builtins.toJSON [ e.accessor e.accessed ]) rawEdges;
  in map (group: builtins.head group) (builtins.attrValues grouped);

  # Filtered DOT output
  filteredDotOutput = ''
    digraph dependencies {
      rankdir=LR;
      node [shape=box, fontsize=10];
      edge [fontsize=8];

    ${lib.concatMapStringsSep "\n" (dep:
      let
        accessor = pathToNode dep.accessor;
        accessed = pathToNode dep.accessed;
      in "  \"${accessor}\" -> \"${accessed}\";"
    ) filteredEdges}
    }
  '';

  # 7. Config values extraction
  sanitizeValue = depth: value:
    if depth <= 0 then "<depth-limit>"
    else
      let
        evalResult = builtins.tryEval (builtins.deepSeq (builtins.typeOf value) value);
      in
        if !evalResult.success then "<error>"
        else
          let
            v = evalResult.value;
            t = builtins.typeOf v;
          in
            if t == "string" then builtins.unsafeDiscardStringContext v
            else if t == "path" then "<path:${toString v}>"
            else if t == "lambda" then "<function>"
            else if t == "list" then map (sanitizeValue (depth - 1)) v
            else if t == "set" then
              if lib.isDerivation v then
                "<derivation:${v.name or "unknown"}>"
              else if builtins.length (builtins.attrNames v) > 50 then
                "<attrset:${toString (builtins.length (builtins.attrNames v))} attrs>"
              else
                lib.mapAttrs (k: sanitizeValue (depth - 1)) v
            else v;  # int, float, bool, null pass through

  # Only extract config for option paths that appear in the dependency graph
  # Filter out invisible options (renamed/obsolete) — those use `abort` which
  # tryEval cannot catch (it only catches throw/assert).
  optionsInGraph = builtins.filter (p:
    optionPathSet ? ${pathKey p} &&
    (let optRes = builtins.tryEval (lib.attrByPath p null nixos.options);
     in optRes.success && optRes.value != null && (optRes.value.visible or true) != false)
  ) keptNodes;

  configValues = builtins.foldl' (acc: path:
    let
      evalResult = builtins.tryEval (
        let val = lib.attrByPath path "__MISSING__" nixos.config;
        in if val == "__MISSING__"
           then null
           else sanitizeValue 5 val
      );
    in
      if evalResult.success && evalResult.value != null
      then lib.recursiveUpdate acc (lib.setAttrByPath path evalResult.value)
      else acc
  ) {} optionsInGraph;

in {
  inherit deps dotOutput filteredDotOutput configValues;
  toplevelPath = toString toplevel;
  depCount = builtins.length deps;
  filteredDepCount = builtins.length filteredEdges;
  optionCount = builtins.length collectOptionPaths;
  keptNodeCount = builtins.length keptNodes;
}
