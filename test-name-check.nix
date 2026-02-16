let 
  config = let self = { x = 10; y = self.x * 2; }; in self; 
  scopeId = builtins.trackAttrset config; 
  yValue = builtins.getAttrTagged scopeId ["y"] config; 
in { 
  x = config.x;
  y = yValue; 
  deps = builtins.getDependencies scopeId; 
}
