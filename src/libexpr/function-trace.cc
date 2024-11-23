#include "function-trace.hh"
#include "logging.hh"
#include "eval.hh"
#include <unordered_map>

namespace nix {

static auto mappi = std::unordered_map<PosIdx, std::pair<uint64_t, uint64_t>>();

void printFunctionCallTrace(EvalState* es) {
    for (auto&& [k,v]: mappi) {
        printMsg(lvlInfo, "%1%,%2%,%3%,", es->positions[k], v.first, v.second);
    }
}

FunctionCallTrace::FunctionCallTrace(PosIdx posidx) : posidx(posidx), start(0) {
    auto duration = std::chrono::high_resolution_clock::now().time_since_epoch();
    auto ns = std::chrono::duration_cast<std::chrono::nanoseconds>(duration);
    start = ns.count();
    // printMsg(lvlInfo, "function-trace entered %1% at %2%", pos, ns.count());
}

FunctionCallTrace::~FunctionCallTrace() {
    auto duration = std::chrono::high_resolution_clock::now().time_since_epoch();
    auto ns = std::chrono::duration_cast<std::chrono::nanoseconds>(duration);
    auto& e = mappi[posidx];
    e.first += 1; // ncalls++
    e.second += ns.count() - start; // elapsed time
    // printMsg(lvlInfo, "function-trace exited %1% at %2%", pos, ns.count());
}

}
