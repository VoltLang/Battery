// Copyright © 2016, Jakob Bornecrantz.  All rights reserved.
// See copyright notice in src/battery/license.volt (BOOST ver. 1.0).
module battery.backend.builder;

import core.exception;
import watt.text.string : endsWith;
import watt.process;
import watt.path : dirSeparator;

import uni = build.core;
import build.util.make;

import battery.interfaces;
import battery.configuration;
import battery.policy.tools;
import battery.backend.command;
import battery.frontend.scanner : deepScan;
import battery.util.path : cleanPath;

import watt.io;


class Builder
{
public:
	alias ArgsKind = ArgsGenerator.Kind;

	mDrv: Driver;

	mega: uni.Target;
	ins: uni.Instance;

	voltaPrint: string;
	voltaBin: uni.Target;


protected:
	/// Store of objects each Lib/Exe produces.
	mObjs: uni.Target[][string];

	mGen: ArgsGenerator;
	mHostGen: ArgsGenerator;


public:
	this(Driver drv)
	{
		this.mDrv = drv;
	}

	fn build(config: Configuration, host: Configuration,
	         libs: Lib[], exes: Exe[])
	{
		this.ins = new uni.Instance();
		this.mega = ins.fileNoRule("__all");

		mGen.setup(config, libs, exes);
		mHostGen.setup(host !is null ? host : config, libs, exes);

		// Setup volta
		voltaTool := config.getTool(VoltaName);
		if (voltaTool !is null) {
			// --cmd-volta on command line, use supplied Volta.
			voltaBin = ins.fileNoRule(voltaTool.cmd);
			voltaPrint = voltaTool.print;
		} else {
			// Need to build volta ourself.
			exe := findVolta(exes);
			voltaBin = makeTargetVolted(ref mHostGen, exe);
			voltaPrint = VoltaPrint;
		}

		// Make sure each library is built.
		foreach (lib; libs) {
			makeTargetVoltLibrary(ref mGen, lib);
		}

		// Generate rules for all the executables.
		foreach (exe; exes) {
			mega.deps ~= makeTargetExe(ref mGen, exe);
		}

		// Do the build.
		try {
			uni.doBuild(mega, 8, config.env);
		} catch (Exception e) {
			mDrv.abort(e.msg);
		}
	}

	fn makeTargetExeBc(ref gen: ArgsGenerator, exe: Exe) uni.Target
	{
		bcName := gen.genVoltExeBc(exe.name);
		depName := gen.genVoltExeDep(exe.name);

		d := ins.file(depName);
		bc := ins.fileNoRule(bcName);
		bc.deps = new uni.Target[](exe.srcVolt.length);

		// Do dependancy tracking on source.
		foreach (i, src; exe.srcVolt) {
			bc.deps[i] = ins.file(src);
		}

		// Depend on the compiler.
		bc.deps ~= [voltaBin];

		// Get all of the arguments.
		args := gen.genVoltArgs(exe, ArgsKind.VoltaSrc, null) ~
			["-o", bcName, "--emit-bitcode", "-c",
			"--dep", depName] ~ exe.srcVolt;

		// This is mostly for Volta.
		if (exe.isInternalD) {
			args ~= "--internal-d";
			foreach (src; exe.srcD) {
				bc.deps ~= ins.file(src);
				args ~= src;
			}
		}

		// Make the rule.
		bc.rule = new uni.Rule();
		bc.rule.cmd = voltaBin.name;
		bc.rule.print = voltaPrint ~ bc.name;
		bc.rule.args = args;
		bc.rule.outputs = [bc, d];

		importDepFile(ins, depName);

		return bc;
	}

	fn makeTargetExe(ref gen: ArgsGenerator, exe: Exe) uni.Target
	{
		oName := gen.genVoltExeO(exe.name);

		// Build bitcode and object
		bc := makeTargetExeBc(ref gen, exe);
		o := makeHelperBitcodeToObj(ref gen, bc, oName);

		// For the bitcode file and extra inputs.
		aux : uni.Target[] = [o];

		// Setup C targets.
		foreach (src; exe.srcC) {
			aux ~= makeTargetC(ref gen, src);
		}

		// Add additional object and library files.
		foreach (obj; exe.srcObj) {
			aux ~= ins.file(obj);
		}

		// Put the extra sources here.
		mObjs[exe.name] = aux;

		//
		// Make the binary build rule.
		//

		name := exe.bin is null ? exe.name : exe.bin;
		if (mGen.config.platform == Platform.MSVC && !endsWith(name, ".exe")) {
			name ~= ".exe";
		}

		t := ins.fileNoRule(name);

		// Add deps and return files to be added to arguments.
		fn cb(base: Base) string[] {
			r := base.name in mObjs;
			if (r is null) {
				return null;
			}

			targets := *r;
			t.deps ~= targets;

			ret: string[];
			foreach (d; targets) {
				ret ~= d.name;
			}
			return ret;
		}

		// Get the linker.
		linker := gen.config.linkerCmd;
		args: string[];

		final switch (gen.config.linkerKind) with (LinkerKind) {
		case Link: // MSVC
			// Generate arguments and collect deps.
			args = gen.genVoltArgs(exe, ArgsKind.LinkLink, cb) ~
				["/out:" ~ name];
			break;
		case Clang:
			// Generate arguments and collect deps.
			args = gen.genVoltArgs(exe, ArgsKind.ClangLink, cb) ~
				["-o", name];
			break;
		case Invalid: assert(false);
		}

		// Make the rule.
		t.rule = new uni.Rule();
		t.rule.cmd = linker.cmd;
		t.rule.print = linker.print ~ t.name;
		t.rule.args = linker.args ~ args;
		t.rule.outputs = [t];

		return t;
	}

	fn makeTargetC(ref gen: ArgsGenerator, src: string) uni.Target
	{
		obj := gen.genFileO(src);

		tc := ins.fileNoRule(obj);
		tc.deps = [ins.file(src)];

		c := gen.config.ccCmd;
		assert(gen.config.ccKind == CCKind.Clang);

		tc.rule = new uni.Rule();
		tc.rule.cmd = c.cmd;
		tc.rule.args = c.args ~ [src, "-c", "-o", obj];
		tc.rule.print = c.print ~ obj;
		tc.rule.outputs = [tc];

		return tc;
	}

	fn makeTargetAsm(ref gen: ArgsGenerator, src: string) uni.Target
	{
		obj := gen.genFileO(src);

		tasm := ins.fileNoRule(obj);
		tasm.deps = [ins.file(src)];

		tasm.rule = new uni.Rule();
		tasm.rule.cmd = gen.config.nasmCmd.cmd;
		tasm.rule.args = gen.config.nasmCmd.args ~ [src, "-o", obj];
		tasm.rule.print = gen.config.nasmCmd.print ~ obj;
		tasm.rule.outputs = [tasm];

		return tasm;
	}

	fn makeTargetVolted(ref gen: ArgsGenerator, exe: Exe) uni.Target
	{
		srcDir := exe.srcDir;
		mainFile := srcDir ~ dirSeparator ~ "main.d";
		files := deepScan(mDrv, srcDir, ".d");
		name := gen.genVolted();

		t := ins.fileNoRule(name);
		t.deps = new uni.Target[](files.length);
		foreach (i, file; files) {
			t.deps[i] = ins.file(file);
		}

		t.rule = new uni.Rule();

		c := gen.config.rdmdCmd;

		args := c.args ~ [
			"--build-only",
			"-I" ~ srcDir,
			"-of" ~ t.name
		];

		foreach (arg; exe.srcObj) {
			args ~= arg;
		}
		foreach (arg; exe.libPaths) {
			args ~= ("-L-L" ~ arg);
		}
		foreach (arg; exe.libs) {
			args ~= ("-L-l" ~ arg);
		}
		foreach (arg; exe.xlinker) {
			args ~= ("-L" ~ arg);
		}
		args ~= mainFile;

		t.rule.outputs = [t];
		t.rule.cmd = c.cmd;
		t.rule.args = args;
		t.rule.print = c.print ~ t.name;

		return t;
	}

	fn makeTargetVoltLibrary(ref gen: ArgsGenerator, lib: Lib) uni.Target
	{
		files := deepScan(mDrv, lib.srcDir, ".volt");
		bcName := gen.genVoltLibraryBc(lib.name);
		oName := gen.genVoltLibraryO(lib.name);

		// Make the bitcode file.
		bc := ins.fileNoRule(bcName);

		// Depends on all of the source files.
		bc.deps = new uni.Target[](files.length);
		foreach (i, file; files) {
			bc.deps[i] = ins.file(file);
		}

		// And depend on the compiler.
		bc.deps ~= voltaBin;

		// Make the rule.
		bc.rule = new uni.Rule();
		bc.rule.cmd = voltaBin.name;
		bc.rule.print = voltaPrint ~ bcName;
		bc.rule.outputs = [bc];
		bc.rule.args = gen.genVoltArgs(lib, ArgsKind.VoltaSrc, null) ~
			["-o", bcName, "-c", "--emit-bitcode"] ~ files;

		// Create the object file for the library.
		o := makeHelperBitcodeToObj(ref gen, bc, oName);

		// Add results into into the store.
		results := [o];
		foreach (a; lib.srcAsm) {
			results ~= makeTargetAsm(ref gen, a);
		}

		mObjs[lib.name] = results;

		return o;
	}

	fn makeHelperBitcodeToObj(ref gen: ArgsGenerator,
	                          bc: uni.Target, oName: string) uni.Target
	{
		// Make o file.
		o := ins.fileNoRule(oName);

		// Depend on the compiler and bitcode file.
		o.deps = [voltaBin, bc];

		// Get clang
		clang := gen.config.clangCmd;

		// Make the rule.
		o.rule = new uni.Rule();
		o.rule.cmd = clang.cmd;
		o.rule.print = clang.print ~ oName;
		o.rule.outputs = [o];
		o.rule.args = clang.args ~ ["-Wno-override-module", // TODO: fix
			"-o", oName, "-c", bc.name];

		return o;
	}


private:
	fn findVolta(exes: Exe[]) Exe
	{
		foreach (exe; exes) {
			if (exe.name == "volta") {
				return exe;
			}
		}
		assert(false);
	}
}
