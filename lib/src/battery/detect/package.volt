// Copyright 2019, Jakob Bornecrantz.
// SPDX-License-Identifier: BSL-1.0
/*!
 * Detection code helpers.
 */
module battery.detect;

public import gdc = battery.detect.gdc;
public import llvm = battery.detect.llvm;
public import nasm = battery.detect.nasm;
public import rdmd = battery.detect.rdmd;
public import msvc = battery.detect.msvc;



struct Argument
{
	path: string;
	llvmConfs: string[];
	msvc: .msvc.FromEnv;
}

struct FromArgs
{
	gdc: .gdc.FromArgs;
	nasm: .nasm.FromArgs;
	rdmd: .rdmd.FromArgs;
	llvm: .llvm.FromArgs;
}

struct Result
{
	gdc: .gdc.Result[];
	msvc: .msvc.Result[];
	llvm: .llvm.Result[];
	nasm: .nasm.Result[];
	rdmd: .rdmd.Result[];
}

fn detect(ref arg: Argument, out result: Result)
{
	llvm.detectFrom(arg.path, arg.llvmConfs, out result.llvm);
	msvc.detect(ref arg.msvc, out result.msvc);

	gdc.detectFromPath(arg.path, out result.gdc);
	nasm.detectFromPath(arg.path, out result.nasm);
	rdmd.detectFromPath(arg.path, out result.rdmd);
}

fn copyAndAddFromArgs(ref input: Result, ref args: FromArgs out result: Result)
{
	result = input;

	gdcRes: gdc.Result;
	if (gdc.detectFromArgs(ref args.gdc, out gdcRes)) {
		result.gdc = gdcRes ~ result.gdc;
	}

	nasmRes: nasm.Result;
	if (nasm.detectFromArgs(ref args.nasm, out nasmRes)) {
		result.nasm = nasmRes ~ result.nasm;
	}

	rdmdRes: rdmd.Result;
	if (rdmd.detectFromArgs(ref args.rdmd, out rdmdRes)) {
		result.rdmd = rdmdRes ~ result.rdmd;
	}

	llvmRes: llvm.Result;
	if (llvm.detectFromArgs(ref args.llvm, out llvmRes)) {
		result.llvm = llvmRes ~ result.llvm;
	}
}
