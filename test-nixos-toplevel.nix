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
      (
        {
          config,
          lib,
          pkgs,
          modulesPath,
          ...
        }:
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

  # Force toplevel evaluation first
  toplevel = nixos.config.system.build.toplevel;

  # 1. Raw deps + deduplication
  rawDeps = builtins.seq toplevel nixos._dependencyTracking.getDependencies;
  deps =
    let
      edgeKey =
        dep:
        builtins.toJSON [
          dep.accessor
          dep.accessed
        ];
      grouped = builtins.groupBy edgeKey rawDeps;
    in
    map (group: builtins.head group) (builtins.attrValues grouped);

  # Convert a path list to a dot-safe node name
  pathToNode = path: builtins.replaceStrings [ "." ] [ "_" ] (lib.concatStringsSep "." path);

  # Generate DOT format for graphviz (full graph)
  dotOutput = ''
    digraph dependencies {
      rankdir=LR;
      node [shape=box, fontsize=10];
      edge [fontsize=8];

    ${lib.concatMapStringsSep "\n" (
      dep:
      let
        accessor = pathToNode dep.accessor;
        accessed = pathToNode dep.accessed;
      in
      "  \"${accessor}\" -> \"${accessed}\";"
    ) deps}
    }
  '';

  # 2. Collect option paths from nixos.options
  # Recursive walk: stop at _type = "option" nodes, use tryEval for robustness
  collectOptionPaths =
    let
      walk =
        prefix: node:
        let
          res = builtins.tryEval (
            if builtins.isAttrs node && (node._type or "") == "option" then
              [ prefix ]
            else if builtins.isAttrs node then
              lib.concatLists (lib.mapAttrsToList (name: child: walk (prefix ++ [ name ]) child) node)
            else
              [ ]
          );
        in
        if res.success then res.value else [ ];
    in
    walk [ ] nixos.options;

  # 3. Option path lookup set (tab-separated keys — attr names never contain tabs)
  pathKey = builtins.concatStringsSep "\t";
  optionPathSet = builtins.listToAttrs (
    map (p: {
      name = pathKey p;
      value = true;
    }) collectOptionPaths
  );

  # 4. Node filtering
  #
  # Two concerns:
  #   a) Internal option-record attributes (_type, type, isDefined, value, …)
  #      that live on option nodes — always noise.
  #   b) _module.args.pkgs.* paths — nixpkgs internals.  We keep top-level
  #      package references (pkgs.<pkg>) and store-path references
  #      (pkgs.<pkg>.out / .outPath) but drop everything else (lib.*,
  #      config.*, build internals like .src, .name, .buildInputs, …).

  # --- (a) option-record internal attributes ---
  optionInternalAttrs = lib.genAttrs [
    "_type" "type" "value" "isDefined" "definitions" "definitionsWithLocations"
    "files" "highestPrio" "loc" "description" "default" "defaultText" "example"
    "readOnly" "internal" "visible" "apply" "declarations" "options"
    "check" "nestedTypes" "deprecationMessage" "relatedPackages"
    "getSubOptions" "getSubModules" "substSubModules" "functor"
  ] (_: true);

  # --- (b) _module.args.pkgs filtering ---
  # Paths that start with ["_module" "args" "pkgs"] get special treatment.
  #   pkgs                             → keep (top-level dep target)
  #   pkgs.lib.*  / pkgs.config.*      → drop (plumbing)
  #   pkgs.<pkg>                       → keep (package reference)
  #   pkgs.<pkg>.out / .outPath        → keep (store-path reference)
  #   pkgs.<anything else deeper>      → drop (build internals)
  pkgsBlacklist = lib.genAttrs [ "lib" "config" ] (_: true);
  pkgsKeptOutputs = lib.genAttrs [ "out" "outPath" ] (_: true);

  isPkgsKept =
    path:
    let
      len = builtins.length path;
      # depth counts components after the "pkgs" element (index 2)
      depth = len - 3;
    in
    if depth <= 0 then
      true                                    # ["_module" "args" "pkgs"] itself
    else if depth == 1 then
      !(pkgsBlacklist ? ${builtins.elemAt path 3})   # pkgs.<X> — keep unless lib/config
    else if depth == 2 then
      let pkg = builtins.elemAt path 3;
          sub = builtins.elemAt path 4;
      in !(pkgsBlacklist ? ${pkg})            # still reject lib.*/config.*
         && pkgsKeptOutputs ? ${sub}          # only keep .out / .outPath
    else
      false;                                  # depth ≥ 3 — always drop

  isKeptNode =
    path:
    let
      len = builtins.length path;

      # Detect _module.args.* paths
      isModuleArgs = len >= 2
        && builtins.elemAt path 0 == "_module"
        && builtins.elemAt path 1 == "args";

      isPkgsPath = isModuleArgs && len >= 3
        && builtins.elemAt path 2 == "pkgs";
    in
    if isPkgsPath then
      # _module.args.pkgs.* — special filter (keep packages, drop lib/config/internals)
      isPkgsKept path
    else if isModuleArgs then
      # _module.args.utils, _module.args.name, etc. — always drop
      false
    else
      let
        # Find the longest option-path prefix of `path`
        longestMatch = builtins.foldl'
          (best: i: if optionPathSet ? ${pathKey (lib.take i path)} then i else best)
          0
          (lib.range 1 len);
      in
      longestMatch > 0
      && (
        # Exact option path — always keep
        longestMatch == len
        # Extension: the first component after the option prefix must NOT be
        # an internal module-system attribute.
        || !(optionInternalAttrs ? ${builtins.elemAt path longestMatch})
      );

  # 5. Collect all unique nodes, partition into kept/pruned
  allNodes =
    let
      allPaths = map (dep: dep.accessor) deps ++ map (dep: dep.accessed) deps;
      grouped = builtins.groupBy pathKey allPaths;
    in
    map (group: builtins.head group) (builtins.attrValues grouped);

  keptNodes = builtins.filter isKeptNode allNodes;
  prunedNodes = builtins.filter (p: !(isKeptNode p)) allNodes;

  keptNodeSet = builtins.listToAttrs (
    map (p: {
      name = pathKey p;
      value = true;
    }) keptNodes
  );
  prunedNodeSet = builtins.listToAttrs (
    map (p: {
      name = pathKey p;
      value = true;
    }) prunedNodes
  );

  # Build adjacency map: accessor key -> list of accessed keys
  adjacencyMap =
    let
      edgesWithKeys = map (dep: {
        srcKey = pathKey dep.accessor;
        dstKey = pathKey dep.accessed;
      }) deps;
      grouped = builtins.groupBy (e: e.srcKey) edgesWithKeys;
    in
    builtins.mapAttrs (k: edges: map (e: e.dstKey) edges) grouped;

  # 6. Transitive edges via genericClosure
  # For each kept source, BFS through pruned intermediates to find reachable kept targets
  reachableKeptTargets =
    sourceKey:
    let
      closure = builtins.genericClosure {
        startSet = map (k: { key = k; }) (adjacencyMap.${sourceKey} or [ ]);
        operator =
          item:
          if keptNodeSet ? ${item.key} then
            [ ] # stop at kept nodes
          else
            map (k: { key = k; }) (adjacencyMap.${item.key} or [ ]);
      };
    in
    builtins.filter (item: keptNodeSet ? ${item.key} && item.key != sourceKey) closure;

  # Build filtered edges
  filteredEdges =
    let
      keptSourceKeys = builtins.filter (k: adjacencyMap ? ${k}) (map pathKey keptNodes);
      rawEdges = lib.concatMap (
        srcKey:
        map (item: {
          accessor = lib.splitString "\t" srcKey;
          accessed = lib.splitString "\t" item.key;
        }) (reachableKeptTargets srcKey)
      ) keptSourceKeys;
      # Deduplicate filtered edges
      grouped = builtins.groupBy (
        e:
        builtins.toJSON [
          e.accessor
          e.accessed
        ]
      ) rawEdges;
    in
    map (group: builtins.head group) (builtins.attrValues grouped);

  # Filtered DOT output
  filteredDotOutput = ''
    digraph dependencies {
      rankdir=LR;
      node [shape=box, fontsize=10];
      edge [fontsize=8];

    ${lib.concatMapStringsSep "\n" (
      dep:
      let
        accessor = pathToNode dep.accessor;
        accessed = pathToNode dep.accessed;
      in
      "  \"${accessor}\" -> \"${accessed}\";"
    ) filteredEdges}
    }
  '';

  # 7. Graph-leaf detection
  #
  # A node is a "leaf" if no other kept node is a descendant of it.
  # We build a set of all proper prefixes of kept node paths; any node
  # whose key appears in that set is a parent and should NOT be serialized.
  parentKeySet =
    let
      allPrefixes = lib.concatMap (p:
        let len = builtins.length p;
        in map (i: pathKey (lib.take i p)) (lib.range 1 (len - 1))
      ) keptNodes;
    in
    builtins.listToAttrs (map (k: { name = k; value = true; }) allPrefixes);

  # Leaf nodes: kept nodes with no descendants in the graph.
  # Exclude _module.args.* (packages/utils aren't config values).
  leafNodes = builtins.filter (p:
    let
      key = pathKey p;
      isModuleArgs = builtins.length p >= 2
        && builtins.elemAt p 0 == "_module"
        && builtins.elemAt p 1 == "args";
    in
    !(parentKeySet ? ${key})
    && !isModuleArgs
  ) keptNodes;

  # 8. Config values extraction — only for leaf nodes
  # Uses builtins.tryCatchAll which catches ALL evaluation errors (not just
  # throw/assert like tryEval), so we can safely attempt any config value.
  sanitizeValue =
    depth: value:
    if depth <= 0 then
      "<depth-limit>"
    else
      let t = builtins.typeOf value;
      in
      if t == "string" then
        builtins.unsafeDiscardStringContext value
      else if t == "path" then
        "<path:${toString value}>"
      else if t == "lambda" then
        "<function>"
      else if t == "list" then
        map (sanitizeValue (depth - 1)) value
      else if t == "set" then
        if lib.isDerivation value then
          "<derivation:${value.name or "unknown"}>"
        else if builtins.length (builtins.attrNames value) > 50 then
          "<attrset:${toString (builtins.length (builtins.attrNames value))} attrs>"
        else
          lib.mapAttrs (_: sanitizeValue (depth - 1)) value
      else
        value; # int, float, bool, null pass through

  # Build config values tree by grouping paths by first component and recursing.
  # This avoids O(n) recursive lib.recursiveUpdate calls which cause stack overflow.
  configValues =
    let
      # Sentinel value to distinguish "missing/failed" from real null config values
      _missing = { _isMissing = true; };

      # Evaluate a single leaf path to a sanitized value, or _missing on failure.
      # tryCatchAll catches ALL errors and deeply evaluates the result.
      evalLeaf = path:
        let
          evalResult = builtins.tryCatchAll (
            let
              val = lib.attrByPath path _missing nixos.config;
            in
            if val == _missing then _missing else sanitizeValue 5 val
          );
        in
        if evalResult.success && evalResult.value != _missing then evalResult.value else _missing;

      # Build a nested attrset from a list of { path; value; } entries
      # by grouping on first path component and recursing
      buildTree = entries:
        let
          # Partition into leaves (path length 1) and branches (path length > 1)
          leaves = builtins.filter (e: builtins.length e.path == 1) entries;
          branches = builtins.filter (e: builtins.length e.path > 1) entries;

          # Group branches by their first path component
          grouped = builtins.groupBy (e: builtins.head e.path) branches;

          # Recursively build sub-trees
          subTrees = builtins.mapAttrs (_: subEntries:
            buildTree (map (e: {
              path = builtins.tail e.path;
              inherit (e) value;
            }) subEntries)
          ) grouped;

          # Direct leaf values
          leafAttrs = builtins.listToAttrs (map (e: {
            name = builtins.head e.path;
            inherit (e) value;
          }) leaves);
        in
        leafAttrs // subTrees;

      # Create entries from leaf nodes, filtering out failures
      entries = builtins.concatMap (path:
        let val = evalLeaf path;
        in if val != _missing then [{ inherit path; value = val; }] else []
      ) leafNodes;
    in
    buildTree entries;

in
{
  inherit
    deps
    dotOutput
    filteredDotOutput
    configValues
    leafNodes
    ;
  toplevelPath = toString toplevel;
  depCount = builtins.length deps;
  filteredDepCount = builtins.length filteredEdges;
  optionCount = builtins.length collectOptionPaths;
  keptNodeCount = builtins.length keptNodes;
  leafNodeCount = builtins.length leafNodes;
}
