#include "nix/expr/attr-set.hh"
#include "nix/expr/eval-inline.hh"

#include <algorithm>

namespace nix {

Bindings Bindings::emptyBindings;

/* Allocate a new array of attributes for an attribute set with a specific
   capacity. The space is implicitly reserved after the Bindings
   structure. */
Bindings * EvalMemory::allocBindings(size_t capacity)
{
    if (capacity == 0)
        return &Bindings::emptyBindings;
    if (capacity > std::numeric_limits<Bindings::size_type>::max())
        throw Error("attribute set of size %d is too big", capacity);
    stats.nrAttrsets++;
    stats.nrAttrsInAttrsets += capacity;
    return new (allocBytes(sizeof(Bindings) + sizeof(Attr) * capacity)) Bindings();
}

Value & BindingsBuilder::alloc(Symbol name, PosIdx pos)
{
    auto value = mem.get().allocValue();
    bindings->push_back(Attr(name, value, pos));
    return *value;
}

Value & BindingsBuilder::alloc(std::string_view name, PosIdx pos)
{
    return alloc(symbols.get().create(name), pos);
}

void Bindings::sort()
{
    std::sort(attrs, attrs + numAttrs);
}

void Bindings::initProvenance(EvalMemory & mem)
{
    if (!provenance) {
        provenance = new (mem.allocBytes(sizeof(*provenance))) ProvenanceData();
        mem.hasAnyTrackedBindings = true;
    }
}

AttrProvenance* Bindings::getProvenance(Symbol name)
{
    if (!provenance) return nullptr;
    auto it = provenance->map.find(name);
    return it != provenance->map.end() ? &it->second : nullptr;
}

const AttrProvenance* Bindings::getProvenance(Symbol name) const
{
    if (!provenance) return nullptr;
    auto it = provenance->map.find(name);
    return it != provenance->map.end() ? &it->second : nullptr;
}

void Bindings::setProvenance(Symbol name, AttrProvenance prov)
{
    if (provenance) provenance->map[name] = std::move(prov);
}

void Bindings::setTrackingPath(std::vector<Symbol> path)
{
    if (provenance) provenance->path = std::move(path);
}

Value & Value::mkAttrs(BindingsBuilder & bindings)
{
    mkAttrs(bindings.finish());
    return *this;
}

} // namespace nix
