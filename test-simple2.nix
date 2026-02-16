# Simulate module system fixpoint
let
  # Create a fixpoint manually
  fixpoint = let
    self = {
      a = 1;
      b = self.a + 1;
      c = self.b + self.a;
    };
  in self;
  
  scopeId = builtins.trackAttrset fixpoint;
  
  # Track b
  bValue = builtins.getAttrTagged scopeId ["b"] fixpoint;
  # Track c  
  cValue = builtins.getAttrTagged scopeId ["c"] fixpoint;
  
  deps = builtins.getDependencies scopeId;
in {
  a = fixpoint.a;
  b = bValue;
  c = cValue;
  inherit deps scopeId;
}
