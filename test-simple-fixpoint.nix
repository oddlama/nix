let
  # Create a simple fixpoint with explicit self reference
  config = let self = {
    base = 10;
    derived = self.base * 2;
  }; in self;
  
  scopeId = builtins.trackAttrset config;
  
  # Track derived
  derivedValue = builtins.getAttrTagged scopeId ["derived"] config;
  deps = builtins.getDependencies scopeId;
  
in {
  base = config.base;
  inherit derivedValue deps;
}
