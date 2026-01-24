#include "nix/expr/primops.hh"
#include "nix/expr/eval-inline.hh"
#include "nix/expr/provenance.hh"
#include "nix/util/position.hh"

namespace nix {

/**
 * Convert a Provenance tree to a Nix attrset.
 */
static void provenanceToValue(EvalState & state, const Provenance * prov, Value & result, Value & trackedValue)
{
    auto attrs = state.buildBindings(5);

    // identifier
    auto & identifierVal = attrs.alloc(state.symbols.create("identifier"));
    if (prov->identifier) {
        identifierVal = *prov->identifier;
    } else {
        identifierVal.mkNull();
    }

    // kind
    attrs.alloc(state.symbols.create("kind")).mkString(prov->kind, state.mem);

    // value - the actual tracked value
    attrs.alloc(state.symbols.create("value")) = trackedValue;

    // provenance - source location
    auto & provenanceAttr = attrs.alloc(state.symbols.create("provenance"));
    if (prov->pos != noPos) {
        auto pos = state.positions[prov->pos];
        auto posAttrs = state.buildBindings(3);

        // file
        if (auto * path = std::get_if<SourcePath>(&pos.origin)) {
            posAttrs.alloc(state.symbols.create("file")).mkString(path->to_string(), state.mem);
        } else if (auto * s = std::get_if<Pos::String>(&pos.origin)) {
            posAttrs.alloc(state.symbols.create("file")).mkString("«string»", state.mem);
        } else if (auto * s = std::get_if<Pos::Stdin>(&pos.origin)) {
            posAttrs.alloc(state.symbols.create("file")).mkString("«stdin»", state.mem);
        }

        // line
        posAttrs.alloc(state.symbols.create("line")).mkInt(pos.line);

        // column
        posAttrs.alloc(state.symbols.create("column")).mkInt(pos.column);

        provenanceAttr.mkAttrs(posAttrs);
    } else {
        provenanceAttr.mkNull();
    }

    // dependencies - recursive provenance structures
    auto & depsVal = attrs.alloc(state.symbols.create("dependencies"));
    if (prov->deps.empty()) {
        auto list = state.buildList(0);
        depsVal.mkList(list);
    } else {
        auto list = state.buildList(prov->deps.size());
        for (size_t i = 0; i < prov->deps.size(); i++) {
            list[i] = state.allocValue();
            // For dependencies, we pass a null value placeholder since we don't have the original values
            Value nullVal;
            nullVal.mkNull();
            provenanceToValue(state, prov->deps[i], *list[i], nullVal);
        }
        depsVal.mkList(list);
    }

    result.mkAttrs(attrs);
}

void prim_trackProvenance(EvalState & state, const PosIdx pos, Value ** args, Value & v)
{
    // args[0] is the identifier (any Nix type)
    // args[1] is the value to track

    Value * identifier = args[0];
    Value * value = args[1];

    // Get source position from the value (before forcing if it's a thunk)
    PosIdx sourcePos = state.getValueSourcePos(*value);

    // Check if value already has provenance
    auto existing = state.getProvenance(value);

    // Force the value to determine type (but not deeply for compounds)
    state.forceValue(*value, pos);

    // If sourcePos is still noPos, try to use the position from after forcing
    if (sourcePos == noPos) {
        sourcePos = state.getValueSourcePos(*value);
    }
    // If still noPos, use the call site position
    if (sourcePos == noPos) {
        sourcePos = pos;
    }

    if (value->type() == nAttrs) {
        // Handle attrset: create a new attrset where each attribute is tracked
        auto & attrs = *value->attrs();
        auto newAttrs = state.buildBindings(attrs.size());

        for (auto & attr : attrs) {
            auto & newVal = newAttrs.alloc(attr.name);

            // Create a thunk that will apply trackProvenance to each attribute
            // For now, we directly track each attribute value
            state.forceValue(*attr.value, pos);

            PosIdx attrSourcePos = attr.pos;
            if (attrSourcePos == noPos) {
                attrSourcePos = state.getValueSourcePos(*attr.value);
            }
            if (attrSourcePos == noPos) {
                attrSourcePos = pos;
            }

            newVal = *attr.value;

            // Get existing provenance on the attribute value
            auto attrExisting = state.getProvenance(attr.value);

            const Provenance * prov;
            if (attrExisting) {
                // Create new root with existing as dependency
                prov = state.provenanceInterner.intern(identifier, "definition", attrSourcePos, {attrExisting});
            } else {
                // Create new leaf node
                prov = state.provenanceInterner.intern(identifier, "definition", attrSourcePos, {});
            }
            state.setProvenance(&newVal, prov);
        }

        v.mkAttrs(newAttrs);
    } else if (value->type() == nList) {
        // Handle list: create a new list where each element is tracked
        auto list = state.buildList(value->listSize());

        for (size_t i = 0; i < value->listSize(); i++) {
            list[i] = state.allocValue();
            auto * elem = value->listView()[i];
            state.forceValue(*elem, pos);

            PosIdx elemSourcePos = state.getValueSourcePos(*elem);
            if (elemSourcePos == noPos) {
                elemSourcePos = pos;
            }

            *list[i] = *elem;

            // Get existing provenance on the element
            auto elemExisting = state.getProvenance(elem);

            const Provenance * prov;
            if (elemExisting) {
                prov = state.provenanceInterner.intern(identifier, "definition", elemSourcePos, {elemExisting});
            } else {
                prov = state.provenanceInterner.intern(identifier, "definition", elemSourcePos, {});
            }
            state.setProvenance(list[i], prov);
        }

        v.mkList(list);
    } else {
        // Scalar value: copy and attach provenance directly
        v = *value;

        const Provenance * prov;
        if (existing) {
            // Create new root node with existing provenance as dependency
            prov = state.provenanceInterner.intern(identifier, "definition", sourcePos, {existing});
        } else {
            // Create new leaf provenance node (no dependencies)
            prov = state.provenanceInterner.intern(identifier, "definition", sourcePos, {});
        }
        state.setProvenance(&v, prov);
    }
}

static RegisterPrimOp primop_trackProvenance({
    .name = "trackProvenance",
    .args = {"identifier", "value"},
    .doc = R"(
        Attach provenance tracking information to a value.

        The *identifier* can be any Nix value and is used to identify the source
        of the value. The *value* is the value to track.

        For compound values (attrsets and lists), each element is tracked independently
        with the same identifier. This preserves lazy evaluation.

        If the value already has provenance information, the new provenance is added
        as a parent node with the existing provenance as a dependency, creating a
        provenance chain.

        Returns the value unchanged (semantically), but with provenance attached.

        Example:
        ```nix
        let
          a = builtins.trackProvenance ["my" "identifier"] 42;
        in builtins.getProvenance a
        ```
    )",
    .fun = prim_trackProvenance,
    .experimentalFeature = Xp::ProvenanceTracking,
});

void prim_getProvenance(EvalState & state, const PosIdx pos, Value ** args, Value & v)
{
    // Force the value
    state.forceValue(*args[0], pos);

    auto prov = state.getProvenance(args[0]);
    if (!prov) {
        v.mkNull();
        return;
    }

    provenanceToValue(state, prov, v, *args[0]);
}

static RegisterPrimOp primop_getProvenance({
    .name = "getProvenance",
    .args = {"value"},
    .doc = R"(
        Get the provenance information attached to a value.

        Returns `null` if the value has no provenance tracking.

        Otherwise, returns an attribute set with the following structure:
        ```nix
        {
          identifier = <any-nix-value>;  # user-provided, null if auto-merged
          kind = "definition" | "binary_add" | "string_interpolation" | ...;
          value = <the-actual-value>;
          provenance = {
            file = "/path/to/file.nix";
            line = 42;
            column = 5;
          };
          dependencies = [
            # recursive provenance structures
            # empty list for leaf nodes
          ];
        }
        ```

        Example:
        ```nix
        let
          a = builtins.trackProvenance "myId" 42;
        in builtins.getProvenance a
        ```
    )",
    .fun = prim_getProvenance,
    .experimentalFeature = Xp::ProvenanceTracking,
});

void prim_removeProvenance(EvalState & state, const PosIdx pos, Value ** args, Value & v)
{
    // Force the value
    state.forceValue(*args[0], pos);

    // Copy the value
    v = *args[0];

    // Remove provenance from the copy
    state.removeProvenance(&v);
}

static RegisterPrimOp primop_removeProvenance({
    .name = "removeProvenance",
    .args = {"value"},
    .doc = R"(
        Remove provenance tracking information from a value.

        Returns the value without any provenance attached.

        Example:
        ```nix
        let
          a = builtins.trackProvenance "myId" 42;
          b = builtins.removeProvenance a;
        in builtins.getProvenance b  # returns null
        ```
    )",
    .fun = prim_removeProvenance,
    .experimentalFeature = Xp::ProvenanceTracking,
});

} // namespace nix
