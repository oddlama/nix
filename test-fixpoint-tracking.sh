#!/usr/bin/env bash
# Test script for fixpoint dependency tracking

NIX_CMD="./build/src/nix/nix"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

PASS=0
FAIL=0

check() {
    local name="$1"
    local expr="$2"
    local expected="$3"

    local result
    result=$($NIX_CMD eval --expr "$expr" 2>&1) || true

    if [ "$result" = "$expected" ]; then
        echo -e "${GREEN}PASS${NC}: $name"
        ((PASS++))
    else
        echo -e "${RED}FAIL${NC}: $name"
        echo "  Expected: $expected"
        echo "  Got:      $result"
        ((FAIL++))
    fi
}

echo "=== Fixpoint Dependency Tracking Tests ==="
echo ""

# Test 1: Basic dependency tracking
check "Basic: c depends on a and b" \
    'builtins.getAttrWithTracking ["c"] (builtins.fixWithTracking (self: { a = 1; b = 2; c = self.a + self.b; }))' \
    '{ dependencies = [ { accessed = [ "a" ]; accessor = [ "c" ]; } { accessed = [ "b" ]; accessor = [ "c" ]; } ]; value = 3; }'

# Test 2: No dependencies
check "No deps: a has no dependencies" \
    'builtins.getAttrWithTracking ["a"] (builtins.fixWithTracking (self: { a = 1; b = 2; c = self.a + self.b; }))' \
    '{ dependencies = [ ]; value = 1; }'

# Test 3: Function with lexical scoping - f is defined accessing c, so when called from x, the dependency is attributed to f
check "Function lexical scoping" \
    'builtins.getAttrWithTracking ["x"] (builtins.fixWithTracking (self: { f = y: self.c + y; x = self.f 1; c = 2; }))' \
    '{ dependencies = [ { accessed = [ "f" ]; accessor = [ "x" ]; } { accessed = [ "c" ]; accessor = [ "f" ]; } ]; value = 3; }'

# Test 4: Nested attribute access
check "Nested attrs: b depends on a.x" \
    'builtins.getAttrWithTracking ["b"] (builtins.fixWithTracking (self: { a.x = 1; b = self.a.x; }))' \
    '{ dependencies = [ { accessed = [ "a" "x" ]; accessor = [ "b" ]; } ]; value = 1; }'

# Test 5: Multiple levels of indirection
check "Chain: d -> c -> b -> a" \
    '(builtins.getAttrWithTracking ["d"] (builtins.fixWithTracking (self: { a = 1; b = self.a; c = self.b; d = self.c; }))).value' \
    '1'

# Test 6: Using builtins.getAttr
check "builtins.getAttr tracking" \
    'builtins.getAttrWithTracking ["b"] (builtins.fixWithTracking (self: { a = 1; b = builtins.getAttr "a" self; }))' \
    '{ dependencies = [ { accessed = [ "a" ]; accessor = [ "b" ]; } ]; value = 1; }'

# Test 7: Unforced thunks have no deps
check "Unforced thunks" \
    'builtins.getAttrWithTracking ["a"] (builtins.fixWithTracking (self: { a = 1; b = self.a + self.c; c = 99; }))' \
    '{ dependencies = [ ]; value = 1; }'

# Test 8: Error on non-tracked attrset
check_contains() {
    local name="$1"
    local expr="$2"
    local expected_substr="$3"

    local result
    result=$($NIX_CMD eval --expr "$expr" 2>&1) || true

    if [[ "$result" == *"$expected_substr"* ]]; then
        echo -e "${GREEN}PASS${NC}: $name"
        ((PASS++))
    else
        echo -e "${RED}FAIL${NC}: $name"
        echo "  Expected to contain: $expected_substr"
        echo "  Got:      $result"
        ((FAIL++))
    fi
}

check_contains "Error on non-tracked attrset" \
    'builtins.getAttrWithTracking ["a"] { a = 1; }' \
    "attrset is not tracked (not created with fixWithTracking)"

# Test 9: Attribute with // operator - order may vary
check_contains "// operator tracking (a dep)" \
    'builtins.getAttrWithTracking ["c"] (builtins.fixWithTracking (self: { a = { x = 1; }; b = { y = 2; }; c = (self.a // self.b).y; }))' \
    '{ accessed = [ "a" ]; accessor = [ "c" ]; }'

check_contains "// operator tracking (b dep)" \
    'builtins.getAttrWithTracking ["c"] (builtins.fixWithTracking (self: { a = { x = 1; }; b = { y = 2; }; c = (self.a // self.b).y; }))' \
    '{ accessed = [ "b" ]; accessor = [ "c" ]; }'

check "// operator value" \
    '(builtins.getAttrWithTracking ["c"] (builtins.fixWithTracking (self: { a = { x = 1; }; b = { y = 2; }; c = (self.a // self.b).y; }))).value' \
    '2'

# Test 10: Self-referencing attribute (should not cause infinite loop in tracking)
check "Self access in fixpoint" \
    '(builtins.getAttrWithTracking ["a"] (builtins.fixWithTracking (self: { a = 1; b = self.b or 2; }))).value' \
    '1'

# Test 11: Multiple getAttrWithTracking calls accumulate dependencies
check "Dependencies accumulate" \
    'let s = builtins.fixWithTracking (self: { a = 1; b = self.a; c = self.a; }); in (builtins.getAttrWithTracking ["b"] s).dependencies' \
    '[ { accessed = [ "a" ]; accessor = [ "b" ]; } ]'

# Test 12: Conditional dependency
check "Conditional dep (true branch)" \
    'builtins.getAttrWithTracking ["c"] (builtins.fixWithTracking (self: { a = 1; b = 2; cond = true; c = if self.cond then self.a else self.b; }))' \
    '{ dependencies = [ { accessed = [ "cond" ]; accessor = [ "c" ]; } { accessed = [ "a" ]; accessor = [ "c" ]; } ]; value = 1; }'

check "Conditional dep (false branch)" \
    'builtins.getAttrWithTracking ["c"] (builtins.fixWithTracking (self: { a = 1; b = 2; cond = false; c = if self.cond then self.a else self.b; }))' \
    '{ dependencies = [ { accessed = [ "cond" ]; accessor = [ "c" ]; } { accessed = [ "b" ]; accessor = [ "c" ]; } ]; value = 2; }'

# Test 13: List element access
check "List in tracked set" \
    '(builtins.getAttrWithTracking ["b"] (builtins.fixWithTracking (self: { a = [1 2 3]; b = builtins.elemAt self.a 1; }))).value' \
    '2'

# Test 14: Multiple functions with lexical scoping
# result accesses add and mult (even though mult is passed as an argument to add)
# add accesses base, mult accesses factor
check "Multiple function lexical scoping" \
    'builtins.getAttrWithTracking ["result"] (builtins.fixWithTracking (self: {
        add = a: b: self.base + a + b;
        mult = x: self.factor * x;
        base = 10;
        factor = 2;
        result = self.add (self.mult 3) 5;
    }))' \
    '{ dependencies = [ { accessed = [ "add" ]; accessor = [ "result" ]; } { accessed = [ "base" ]; accessor = [ "add" ]; } { accessed = [ "mult" ]; accessor = [ "result" ]; } { accessed = [ "factor" ]; accessor = [ "mult" ]; } ]; value = 21; }'

# Test 15: Nested function calls (curried)
check "Curried function" \
    'builtins.getAttrWithTracking ["z"] (builtins.fixWithTracking (self: { f = a: b: self.c + a + b; x = self.f 1; z = self.x 2; c = 10; }))' \
    '{ dependencies = [ { accessed = [ "x" ]; accessor = [ "z" ]; } { accessed = [ "f" ]; accessor = [ "x" ]; } { accessed = [ "c" ]; accessor = [ "f" ]; } ]; value = 13; }'

echo ""
echo "=== withDependencyTracking Tests (tree-structured dependencies) ==="
echo ""

# Test 16: Basic withDependencyTracking (new 2-arg API)
check "withDependencyTracking basic" \
    'let config = { a = 1; b = config.a + 1; }; in builtins.withDependencyTracking ["b"] config' \
    '{ dependencies = [ { accessed = [ "a" ]; accessor = [ "b" ]; } ]; value = 2; }'

# Test 17: withDependencyTracking transitive deps - now tree-structured!
# c -> b -> a becomes: c accesses b, b accesses a (order may vary)
check_contains "withDependencyTracking transitive tree (c->b)" \
    'let config = { a = 1; b = config.a; c = config.b; }; in builtins.withDependencyTracking ["c"] config' \
    '{ accessed = [ "b" ]; accessor = [ "c" ]; }'

check_contains "withDependencyTracking transitive tree (b->a)" \
    'let config = { a = 1; b = config.a; c = config.b; }; in builtins.withDependencyTracking ["c"] config' \
    '{ accessed = [ "a" ]; accessor = [ "b" ]; }'

# Test 18: withDependencyTracking with nested attrs (NixOS-like pattern)
check "withDependencyTracking nested attrs" \
    'let config = { services.nginx.enable = config.services.webapp.enable; services.webapp.enable = true; }; in builtins.withDependencyTracking ["services" "nginx" "enable"] config' \
    '{ dependencies = [ { accessed = [ "services" "webapp" "enable" ]; accessor = [ "services" "nginx" "enable" ]; } ]; value = true; }'

# Test 19: withDependencyTracking with conditionals
check "withDependencyTracking conditional" \
    'let config = { enabled = true; value = if config.enabled then 42 else 0; }; in builtins.withDependencyTracking ["value"] config' \
    '{ dependencies = [ { accessed = [ "enabled" ]; accessor = [ "value" ]; } ]; value = 42; }'

# Test 20: withDependencyTracking complex NixOS-like scenario - value check
check "withDependencyTracking NixOS-like value" \
    'let config = {
        services.nginx.enable = config.services.webapp.enable;
        services.webapp.enable = true;
        services.postgresql.enable = config.services.webapp.enable;
        networking.firewall.allowedTCPPorts = if config.services.nginx.enable then [80 443] else [];
    }; in (builtins.withDependencyTracking ["networking" "firewall" "allowedTCPPorts"] config).value' \
    '[ 80 443 ]'

# Test 21: withDependencyTracking captures tree-structured deps
# firewall -> nginx.enable -> webapp.enable
check_contains "withDependencyTracking tree deps (nginx)" \
    'let config = {
        services.nginx.enable = config.services.webapp.enable;
        services.webapp.enable = true;
        networking.firewall.allowedTCPPorts = if config.services.nginx.enable then [80] else [];
    }; in builtins.withDependencyTracking ["networking" "firewall" "allowedTCPPorts"] config' \
    '{ accessed = [ "services" "nginx" "enable" ]; accessor = [ "networking" "firewall" "allowedTCPPorts" ]; }'

check_contains "withDependencyTracking tree deps (webapp)" \
    'let config = {
        services.nginx.enable = config.services.webapp.enable;
        services.webapp.enable = true;
        networking.firewall.allowedTCPPorts = if config.services.nginx.enable then [80] else [];
    }; in builtins.withDependencyTracking ["networking" "firewall" "allowedTCPPorts"] config' \
    '{ accessed = [ "services" "webapp" "enable" ]; accessor = [ "services" "nginx" "enable" ]; }'

echo ""
echo "=== Results ==="
echo -e "${GREEN}Passed: $PASS${NC}"
echo -e "${RED}Failed: $FAIL${NC}"

if [ $FAIL -gt 0 ]; then
    exit 1
fi
