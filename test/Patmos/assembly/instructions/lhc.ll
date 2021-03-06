; RUN: %test_no_runtime_execution

define i32 @main() {
entry:  
  %stack_var_1 = alloca i16, i32 4
  store i16 82, i16* %stack_var_1
  %stack_var_2 = getelementptr inbounds i16* %stack_var_1, i32 3
  store i16 92, i16* %stack_var_2
  
  %asm_result = call { i32, i32 } asm "
		lhc	$0	=	[$2]	
		lhc	$1	=	[$2 + 3]	
		nop
	", "=&r,=r,r"
	(i16* %stack_var_1)
	
  ; Extract results
  %result_1 = extractvalue { i32, i32 } %asm_result, 0
  %result_2 = extractvalue { i32, i32 } %asm_result, 1
  
  ; Check correctness
  %correct_1 = icmp eq i32 %result_1, 82
  %correct_2 = icmp eq i32 %result_2, 92
  %correct = and i1 %correct_1, %correct_2
  
  ; Negate result to ensure 0 is returned on success
  %result_0 = xor i1 %correct, 1 
  
  %result = zext i1 %result_0 to i32
  ret i32 %result
}