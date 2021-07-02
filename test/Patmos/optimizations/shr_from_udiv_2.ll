; RUN: llc < %s | FileCheck %s
; END.
;//////////////////////////////////////////////////////////////////////////////////////////////////
;
; Tests that signed division by 2 is optimized into a sra instruction.
;
;//////////////////////////////////////////////////////////////////////////////////////////////////

; CHECK-LABEL: main:
define i32 @main(i32 %value)  {
entry:
  %0 = sdiv i32 %value, 2

; CHECK: sra $r{{[0-9]+}} = $r{{[0-9]+}}, 1

  ret i32 %0
}
