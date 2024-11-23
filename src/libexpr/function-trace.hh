#pragma once
///@file

#include "eval.hh"

#include <chrono>

namespace nix {

void printFunctionCallTrace(EvalState* es);

struct FunctionCallTrace
{
    PosIdx posidx;
    int64_t start;
    FunctionCallTrace(PosIdx posidx);
    ~FunctionCallTrace();
};
}
