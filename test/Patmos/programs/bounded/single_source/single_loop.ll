; RUN: EXEC_ARGS="0=0 1=1 2=3 3=6 5=15"; \
; RUN: %test_execution
; END.
;//////////////////////////////////////////////////////////////////////////////////////////////////
; 
; Tests that a bounded loop generates single-path code.
;
; The following is the equivalent C code:
; volatile int _1 = 1;
; 
; int main(int iteration_count){
; 	int x = 0;
; 	#pragma loopbound min 0 max 4
; 	for(int i = 0; i<iteration_count; i++){
; 		x += i + _1;
; 	}
; 	return x;
; }
; 
;//////////////////////////////////////////////////////////////////////////////////////////////////

@_1 = global i32 1

define i32 @main(i32 %iteration_count)  {
entry:
  br label %for.cond

for.cond:                                         ; preds = %for.inc, %entry
  %x.0 = phi i32 [ 0, %entry ], [ %add1, %for.inc ]
  %i.0 = phi i32 [ 0, %entry ], [ %inc, %for.inc ]
  %cmp = icmp slt i32 %i.0, %iteration_count
  br i1 %cmp, label %for.body, label %for.end, !llvm.loop !0

for.body:                                         ; preds = %for.cond
  %0 = load volatile i32* @_1
  br label %for.inc

for.inc:                                          ; preds = %for.body
  %add = add nsw i32 %i.0, %0
  %add1 = add nsw i32 %x.0, %add
  %inc = add nsw i32 %i.0, 1
  br label %for.cond

for.end:                                          ; preds = %for.cond
  ret i32 %x.0
}

!0 = metadata !{metadata !0, metadata !1}
!1 = metadata !{metadata !"llvm.loop.bound", i32 0, i32 4}
