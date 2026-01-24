let
  # Test basic tracking
  a = builtins.trackProvenance "A" 1;
  b = builtins.trackProvenance "B" 2;

  # Test passthrough (single tracked operand with untracked)
  c = 10 + a;

  # Test merge (multiple tracked operands)
  d = a + b;

  # Test remove provenance
  e = builtins.removeProvenance d;

in {
  # Basic tracking returns provenance
  test1_hasProvenance = builtins.getProvenance a != null;
  test1_identifier = (builtins.getProvenance a).identifier;
  test1_kind = (builtins.getProvenance a).kind;

  # Passthrough preserves original provenance
  test2_hasProvenance = builtins.getProvenance c != null;
  test2_identifier = (builtins.getProvenance c).identifier;

  # Merge creates new tree node
  test3_hasProvenance = builtins.getProvenance d != null;
  test3_kind = (builtins.getProvenance d).kind;
  test3_identifier = (builtins.getProvenance d).identifier;
  test3_numDeps = builtins.length (builtins.getProvenance d).dependencies;

  # Remove provenance returns null
  test4_noProvenance = builtins.getProvenance e == null;

  # Untracked value has no provenance
  test5_untracked = builtins.getProvenance 42 == null;
}
