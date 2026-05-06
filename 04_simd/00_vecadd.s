	.file	"00_vecadd.cpp"
	.text
	.section	.rodata.str1.1,"aMS",@progbits,1
.LC2:
	.string	"%d %g\n"
	.section	.text.startup,"ax",@progbits
	.p2align 4
	.globl	main
	.type	main, @function
main:
.LFB12:
	.cfi_startproc
	leaq	8(%rsp), %r10
	.cfi_def_cfa 10, 0
	andq	$-32, %rsp
	pushq	-8(%r10)
	pushq	%rbp
	movq	%rsp, %rbp
	.cfi_escape 0x10,0x6,0x2,0x76,0
	pushq	%r10
	.cfi_escape 0xf,0x3,0x76,0x78,0x6
	pushq	%rbx
	subq	$96, %rsp
	.cfi_escape 0x10,0x3,0x2,0x76,0x70
	vmovaps	.LC0(%rip), %ymm0
	vmovaps	%ymm0, -112(%rbp)
	vmovaps	.LC1(%rip), %ymm0
	vmovaps	%ymm0, -80(%rbp)
	vpxor	%xmm0, %xmm0, %xmm0
	vmovdqa	%xmm0, -48(%rbp)
	vmovdqa	%xmm0, -32(%rbp)
#APP
# 11 "00_vecadd.cpp" 1
	# begin loop
# 0 "" 2
#NO_APP
	vmovaps	-80(%rbp), %ymm2
	vaddps	-112(%rbp), %ymm2, %ymm0
	vmovaps	%ymm0, -48(%rbp)
#APP
# 14 "00_vecadd.cpp" 1
	# end loop
# 0 "" 2
#NO_APP
	xorl	%ebx, %ebx
	vzeroupper
	.p2align 4
	.p2align 3
.L2:
	vxorpd	%xmm1, %xmm1, %xmm1
	movl	%ebx, %esi
	movl	$.LC2, %edi
	movl	$1, %eax
	vcvtss2sd	-48(%rbp,%rbx,4), %xmm1, %xmm0
	incq	%rbx
	call	printf
	cmpq	$8, %rbx
	jne	.L2
	addq	$96, %rsp
	xorl	%eax, %eax
	popq	%rbx
	popq	%r10
	.cfi_def_cfa 10, 0
	popq	%rbp
	leaq	-8(%r10), %rsp
	.cfi_def_cfa 7, 8
	ret
	.cfi_endproc
.LFE12:
	.size	main, .-main
	.section	.rodata.cst32,"aM",@progbits,32
	.align 32
.LC0:
	.long	0
	.long	1065353216
	.long	1073741824
	.long	1077936128
	.long	1082130432
	.long	1084227584
	.long	1086324736
	.long	1088421888
	.align 32
.LC1:
	.long	0
	.long	1036831949
	.long	1045220557
	.long	1050253722
	.long	1053609165
	.long	1056964608
	.long	1058642330
	.long	1060320051
	.ident	"GCC: (GNU) 11.5.0 20240719 (Red Hat 11.5.0-5)"
	.section	.note.GNU-stack,"",@progbits
