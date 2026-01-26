let
  fix = f: let x = f x; in x;

  basic = tracked { a = 1; b = 2; };

  withDeps = fix (self: tracked {
    x = 10;
    y = self.x + 1;
  });

  merged = tracked { a = 1; } // tracked { b = 2; };
in {
  test1_isTracked = builtins.isTracked basic;
  test2_hasProv = builtins.getAttrProvenance basic "a" != null;
  # Use seq to force evaluation of y before checking its provenance
  test3_fixDeps = builtins.seq withDeps.y (builtins.length (builtins.getAttrProvenance withDeps "y").dependencies > 0);
  test4_mergeTracked = builtins.isTracked merged;
  test5_regularNotTracked = builtins.isTracked { a = 1; } == false;
}
