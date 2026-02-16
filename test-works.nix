let 
  config = let self = { a = 1; b = self.a + 1; c = self.b + self.a; }; in self; 
  scopeId = builtins.trackAttrset config; 
  bValue = builtins.getAttrTagged scopeId ["b"] config; 
  cValue = builtins.getAttrTagged scopeId ["c"] config; 
in { 
  b = bValue; 
  c = cValue; 
  deps = builtins.getDependencies scopeId; 
}
