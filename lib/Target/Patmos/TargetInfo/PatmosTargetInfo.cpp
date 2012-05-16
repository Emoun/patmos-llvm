//===-- PatmosTargetInfo.cpp - Patmos Target Implementation ---------------===//
//
//                     The LLVM Compiler Infrastructure
//
// This file is distributed under the University of Illinois Open Source
// License. See LICENSE.TXT for details.
//
//===----------------------------------------------------------------------===//

#include "Patmos.h"
#include "llvm/Module.h"
#include "llvm/Support/TargetRegistry.h"
using namespace llvm;

Target llvm::ThePatmosTarget;

extern "C" void LLVMInitializePatmosTargetInfo() { 
  RegisterTarget<Triple::patmos> 
    X(ThePatmosTarget, "patmos", "Patmos [experimental]");
}