let 
  config = let self = { base = 10; derived = self.base * 2; }; in self; 
  scopeId = builtins.trackAttrset config; 
  derivedValue = builtins.getAttrTagged scopeId ["derived"] config; 
in { 
  base = config.base;
  derived = derivedValue; 
  deps = builtins.getDependencies scopeId; 
}
