#include "nix/expr/provenance.hh"

namespace nix {

const Provenance * ProvenanceInterner::intern(
    Value * identifier,
    std::string kind,
    PosIdx pos,
    std::vector<const Provenance *> deps)
{
    // For now, always create a new node.
    // Hash-consing optimization can be added later if needed.
    nodes.push_back(std::make_unique<Provenance>(identifier, std::move(kind), pos, std::move(deps)));
    return nodes.back().get();
}

} // namespace nix
