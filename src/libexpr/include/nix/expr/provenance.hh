#pragma once
///@file

#include "nix/util/pos-table.hh"
#include "nix/util/ref.hh"

#include <string>
#include <vector>
#include <memory>

namespace nix {

struct Value;

/**
 * Provenance info attached to a value (recursive tree structure).
 * Tracks where a value came from and how it was derived.
 */
struct Provenance {
    /**
     * User-defined identifier, any Nix type (nullable).
     * Set by trackProvenance, null for auto-merged operations.
     */
    Value * identifier = nullptr;

    /**
     * The kind of operation that produced this provenance:
     * - "definition": Value explicitly tracked with trackProvenance
     * - "binary_add": a + b (numeric)
     * - "binary_sub": a - b
     * - "binary_mul": a * b
     * - "binary_div": a / b
     * - "list_concat": a ++ b
     * - "attr_merge": a // b
     * - "string_interpolation": "${a}${b}"
     * - etc.
     */
    std::string kind;

    /**
     * Source location where this value was defined or where the operation occurred.
     */
    PosIdx pos;

    /**
     * Child dependencies (empty for leaf nodes created by trackProvenance on
     * values without existing provenance).
     */
    std::vector<const Provenance *> deps;

    Provenance(Value * identifier, std::string kind, PosIdx pos, std::vector<const Provenance *> deps = {})
        : identifier(identifier)
        , kind(std::move(kind))
        , pos(pos)
        , deps(std::move(deps))
    {
    }
};

/**
 * Hash-consing interner for provenance trees.
 * Deduplicates identical subtrees to save memory.
 */
class ProvenanceInterner {
    /**
     * Storage for all provenance nodes.
     * Using vector for stable pointers (we never remove nodes).
     */
    std::vector<std::unique_ptr<Provenance>> nodes;

public:
    /**
     * Create or retrieve an interned provenance node.
     * For now, this always creates a new node (hash-consing optimization
     * can be added later if memory becomes an issue).
     */
    const Provenance * intern(Value * identifier, std::string kind, PosIdx pos, std::vector<const Provenance *> deps = {});

    /**
     * Get the number of interned nodes (for statistics).
     */
    size_t size() const { return nodes.size(); }
};

} // namespace nix
