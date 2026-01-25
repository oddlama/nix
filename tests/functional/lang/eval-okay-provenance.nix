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

  # Test no collision - same value, different provenance
  col_a = builtins.trackProvenance "ColA" 1;
  col_b = builtins.trackProvenance "ColB" 1;  # Same value as col_a!

  # Test string tracking
  str = builtins.trackProvenance "S" "hello";

  # Test float tracking
  flt = builtins.trackProvenance "F" 3.14;

  # Test bool tracking
  bool_t = builtins.trackProvenance "BT" true;
  bool_f = builtins.trackProvenance "BF" false;

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

  # No collision: same integer value, different provenance
  test6_collision_a = (builtins.getProvenance col_a).identifier;
  test6_collision_b = (builtins.getProvenance col_b).identifier;

  # String tracking works
  test7_string_has = builtins.getProvenance str != null;
  test7_string_id = (builtins.getProvenance str).identifier;

  # Float tracking works
  test8_float_has = builtins.getProvenance flt != null;
  test8_float_id = (builtins.getProvenance flt).identifier;

  # Bool tracking works
  test9_bool_t_has = builtins.getProvenance bool_t != null;
  test9_bool_t_id = (builtins.getProvenance bool_t).identifier;
  test9_bool_f_has = builtins.getProvenance bool_f != null;
  test9_bool_f_id = (builtins.getProvenance bool_f).identifier;
}
