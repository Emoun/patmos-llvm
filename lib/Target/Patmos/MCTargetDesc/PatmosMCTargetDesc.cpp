//===-- PatmosMCTargetDesc.cpp - Patmos Target Descriptions -----*- C++ -*-===//
//
//                     The LLVM Compiler Infrastructure
//
// This file is distributed under the University of Illinois Open Source
// License. See LICENSE.TXT for details.
//
//===----------------------------------------------------------------------===//
//
// This file provides Patmos specific target descriptions.
//
//===----------------------------------------------------------------------===//

#include "PatmosMCTargetDesc.h"
#include "PatmosMCAsmInfo.h"
#include "InstPrinter/PatmosInstPrinter.h"
#include "llvm/MC/MCCodeGenInfo.h"
#include "llvm/MC/MCInstrInfo.h"
#include "llvm/MC/MCRegisterInfo.h"
#include "llvm/MC/MCSubtargetInfo.h"
#include "llvm/Support/TargetRegistry.h"

#define GET_INSTRINFO_MC_DESC
#include "PatmosGenInstrInfo.inc"

#define GET_SUBTARGETINFO_MC_DESC
#include "PatmosGenSubtargetInfo.inc"

#define GET_REGINFO_MC_DESC
#include "PatmosGenRegisterInfo.inc"

using namespace llvm;

static MCInstrInfo *createPatmosMCInstrInfo() {
  MCInstrInfo *X = new MCInstrInfo();
  InitPatmosMCInstrInfo(X);
  return X;
}

static MCRegisterInfo *createPatmosMCRegisterInfo(StringRef TT) {
  MCRegisterInfo *X = new MCRegisterInfo();
  InitPatmosMCRegisterInfo(X, Patmos::R1);
  return X;
}

static MCSubtargetInfo *createPatmosMCSubtargetInfo(StringRef TT, StringRef CPU,
                                                    StringRef FS) {
  MCSubtargetInfo *X = new MCSubtargetInfo();
  InitPatmosMCSubtargetInfo(X, TT, CPU, FS);
  return X;
}

static MCCodeGenInfo *createPatmosMCCodeGenInfo(StringRef TT, Reloc::Model RM,
                                                CodeModel::Model CM) {
  MCCodeGenInfo *X = new MCCodeGenInfo();
  X->InitMCCodeGenInfo(RM, CM);
  return X;
}

static MCInstPrinter *createPatmosMCInstPrinter(const Target &T,
                                                unsigned SyntaxVariant,
                                                const MCAsmInfo &MAI,
                                                const MCSubtargetInfo &STI) {
  if (SyntaxVariant == 0)
    return new PatmosInstPrinter(MAI);
  return 0;
}

extern "C" void LLVMInitializePatmosTargetMC() {
  // Register the MC asm info.
  RegisterMCAsmInfo<PatmosMCAsmInfo> X(ThePatmosTarget);

  // Register the MC codegen info.
  TargetRegistry::RegisterMCCodeGenInfo(ThePatmosTarget,
                                        createPatmosMCCodeGenInfo);

  // Register the MC instruction info.
  TargetRegistry::RegisterMCInstrInfo(ThePatmosTarget, createPatmosMCInstrInfo);

  // Register the MC register info.
  TargetRegistry::RegisterMCRegInfo(ThePatmosTarget,
                                    createPatmosMCRegisterInfo);

  // Register the MC subtarget info.
  TargetRegistry::RegisterMCSubtargetInfo(ThePatmosTarget,
                                          createPatmosMCSubtargetInfo);

  // Register the MCInstPrinter.
  TargetRegistry::RegisterMCInstPrinter(ThePatmosTarget,
                                        createPatmosMCInstPrinter);
}