; RUN: llc < %s -mtriple=x86_64-apple-darwin -mcpu=knl | FileCheck %s

;CHECK-LABEL: _inreg16xi32:
;CHECK: vpbroadcastd {{.*}}, %zmm
;CHECK: ret
define   <16 x i32> @_inreg16xi32(i32 %a) {
  %b = insertelement <16 x i32> undef, i32 %a, i32 0
  %c = shufflevector <16 x i32> %b, <16 x i32> undef, <16 x i32> zeroinitializer
  ret <16 x i32> %c
}

;CHECK-LABEL: _inreg8xi64:
;CHECK: vpbroadcastq {{.*}}, %zmm
;CHECK: ret
define   <8 x i64> @_inreg8xi64(i64 %a) {
  %b = insertelement <8 x i64> undef, i64 %a, i32 0
  %c = shufflevector <8 x i64> %b, <8 x i64> undef, <8 x i32> zeroinitializer
  ret <8 x i64> %c
}

;CHECK-LABEL: _inreg16xfloat:
;CHECK: vbroadcastssz {{.*}}, %zmm
;CHECK: ret
define   <16 x float> @_inreg16xfloat(float %a) {
  %b = insertelement <16 x float> undef, float %a, i32 0
  %c = shufflevector <16 x float> %b, <16 x float> undef, <16 x i32> zeroinitializer
  ret <16 x float> %c
}

;CHECK-LABEL: _inreg8xdouble:
;CHECK: vbroadcastsdz {{.*}}, %zmm
;CHECK: ret
define   <8 x double> @_inreg8xdouble(double %a) {
  %b = insertelement <8 x double> undef, double %a, i32 0
  %c = shufflevector <8 x double> %b, <8 x double> undef, <8 x i32> zeroinitializer
  ret <8 x double> %c
}

;CHECK-LABEL: _xmm16xi32
;CHECK: vpbroadcastd
;CHECK: ret
define   <16 x i32> @_xmm16xi32(<16 x i32> %a) {
  %b = shufflevector <16 x i32> %a, <16 x i32> undef, <16 x i32> zeroinitializer
  ret <16 x i32> %b
}

;CHECK-LABEL: _xmm16xfloat
;CHECK: vbroadcastssz
;CHECK: ret
define   <16 x float> @_xmm16xfloat(<16 x float> %a) {
  %b = shufflevector <16 x float> %a, <16 x float> undef, <16 x i32> zeroinitializer
  ret <16 x float> %b
}
