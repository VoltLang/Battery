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

import io = watt.io;


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
	mStore: Store[string];

	mGen: ArgsGenerator;


public:
	this(Driver drv)
	{
		this.mDrv = drv;
	}

	fn build(config: Configuration, boot: Configuration,
	         libs: Lib[], exes: Exe[])
	{
		this.ins = new uni.Instance();
		this.mega = ins.fileNoRule("__all");

		mGen.setup(config, libs, exes);

		// Setup volta
		voltaTool := config.getTool(VoltaName);
		if (voltaTool !is null) {
			// --cmd-volta on command line, use supplied Volta.
			voltaBin = ins.fileNoRule(voltaTool.cmd);
			voltaPrint = voltaTool.print;
		} else {
			// Always use the bootstrap config to build volted.
			assert(boot !is null);

			// Setup a generator just for Volta.
			mVoltaGen: ArgsGenerator;
			mVoltaGen.setup(boot, libs, exes);

			// Need to build volta ourself.
			exe := findVolta(exes);
			voltaBin = makeTargetVolted(ref mVoltaGen, exe);
			voltaPrint = VoltaPrint;
		}

		// Make sure each library is built.
		foreach (lib; libs) {
			store := processLibrary(ref mGen, lib);
			mega.deps ~= store.objs;
		}

		// Generate rules for all the executables.
		foreach (exe; exes) {
			processExe(ref mGen, exe);
			mega.deps ~= makeTargetExe(ref mGen, exe);
		}

		// Do the build.
		try {
			uni.doBuild(mega, 8, config.env);
		} catch (Exception e) {
			mDrv.abort(e.msg);
		}
	}


	/*
	 *
	 * Process functions.
	 *
	 */

	fn processProject(ref gen: ArgsGenerator, b: Project) Store
	{
		// Get the number of objects.
		num := b.srcAsm.length + b.srcObj.length + b.srcC.length;

		store := new Store();

		// Nothing to do here.
		if (num <= 0) {
			return store;
		}

		// Create results list.
		store.objs = new uni.Target[](num);
		count: size_t;

		// Setup C targets.
		foreach (src; b.srcC) {
			store.objs[count++] = makeTargetC(ref gen, src);
		}

		// Add store.objs into into the store.
		foreach (a; b.srcAsm) {
			store.objs[count++] = makeTargetAsm(ref gen, a);
		}

		// Add additional object and library files.
		foreach (obj; b.srcObj) {
			store.objs[count++] = ins.file(obj);
		}

		return store;
	}

	fn processLibrary(ref gen: ArgsGenerator, lib: Lib) Store
	{
		// Object where all parts of the library are stored.
		store: Store;

		// Should we include the library source directly in the binary.
		if (gen.shouldSourceInclude(lib)) {
			store = processProject(ref gen, lib);
		} else if (gen.config.isLTO) {
			store = processProject(ref gen, lib);
			store.objs ~= makeTargetVoltLibraryAr(ref gen, lib);
		} else {
			store = processProject(ref gen, lib);
			store.objs ~= makeTargetVoltLibraryO(ref gen, lib);
		}

		addStore(lib.name, store);
		return store;
	}

	fn processExe(ref gen: ArgsGenerator, exe: Exe) Store
	{
		// Object where all parts of the exe are stored.
		store: Store;

		// Should we generate a 'o' or 'ar' file.
		if (gen.config.isLTO) {
			store = processProject(ref gen, exe);
			store.objs ~= makeTargetExeAr(ref gen, exe);
		} else {
			store = processProject(ref gen, exe);
			store.objs ~= makeTargetExeO(ref gen, exe);
		}

		addStore(exe.name, store);
		return store;
	}


	/*
	 *
	 * Target library functions.
	 *
	 */

	fn makeTargetVoltLibraryGeneric(ref gen: ArgsGenerator, lib: Lib, name: string, flags: ArgsKind) uni.Target
	{
		depName := gen.genVoltDep(lib.name);
		files: string[];
		if (lib.scanForD) {
			files = deepScan(lib.srcDir, ".d");
		} else {
			files = deepScan(lib.srcDir, ".volt");
		}


		// Make the dependancy and target file.
		t := ins.fileNoRule(name);
		d := ins.fileNoRule(depName);
		outputs := [t, d];

		// Depends on all of the source files.
		t.deps = new uni.Target[](files.length);
		foreach (i, file; files) {
			t.deps[i] = ins.file(file);
		}

		// And depend on the compiler.
		t.deps ~= voltaBin;

		// Create arguments.
		flags |= ArgsKind.VoltaSrc;
		args := gen.genVoltArgs(lib, flags, null) ~
			["-o", name, "--dep", depName] ~ files;

		// Should we generate JSON output.
		jsonName := gen.shouldJSON(lib);
		if (jsonName !is null) {
			j := ins.fileNoRule(jsonName);
			args ~= ["-jo", jsonName];
			outputs ~= j;
		}

		// Make the rule.
		rule := new uni.Rule();
		rule.cmd = voltaBin.name;
		rule.print = voltaPrint ~ name;
		rule.args = args;
		rule.outputs = outputs;

		t.rule = rule;

		importDepFile(ins, depName);

		return t;
	}

	fn makeTargetVoltLibraryBc(ref gen: ArgsGenerator, lib: Lib) uni.Target
	{
		bcName := gen.genVoltBc(lib.name);
		return makeTargetVoltLibraryGeneric(ref gen, lib, bcName, ArgsKind.VoltaBc);
	}

	fn makeTargetVoltLibraryAr(ref gen: ArgsGenerator, lib: Lib) uni.Target
	{
		oName := gen.genVoltA(lib.name);
		return makeTargetVoltLibraryGeneric(ref gen, lib, oName, ArgsKind.VoltaAr);
	}

	fn makeTargetVoltLibraryO(ref gen: ArgsGenerator, lib: Lib) uni.Target
	{
		return makeHelperBitcodeToObj(ref gen,
			makeTargetVoltLibraryBc(ref gen, lib));
	}


	/*
	 *
	 * Target exe functions.
	 *
	 */

	fn makeTargetExeGeneric(ref gen: ArgsGenerator, exe: Exe, name: string,
	                        flags: ArgsKind) uni.Target
	{
		depName := gen.genVoltDep(exe.name);
		files := exe.srcVolt;

		// Make the dependancy and target file.
		t := ins.fileNoRule(name);
		d := ins.fileNoRule(depName);
		outputs := [t, d];

		// Do dependancy tracking on source.
		t.deps = new uni.Target[](files.length);
		foreach (i, src; files) {
			t.deps[i] = ins.file(src);
		}

		// Depend on the compiler.
		t.deps ~= voltaBin;

		// Get all of the arguments.
		flags |= ArgsKind.VoltaSrc;
		args := gen.genVoltArgs(exe, flags, null) ~
			["-o", name, "--dep", depName] ~ exe.srcVolt;

		// Should we generate JSON output.
		jsonName := gen.shouldJSON(exe);
		if (jsonName !is null) {
			j := ins.fileNoRule(jsonName);
			args ~= ["-jo", jsonName];
			outputs ~= j;
		}

		// Make the rule.
		rule := new uni.Rule();
		rule.cmd = voltaBin.name;
		rule.print = voltaPrint ~ name;
		rule.args = args;
		rule.outputs = outputs;

		t.rule = rule;

		importDepFile(ins, depName);

		return t;
	}

	fn makeTargetExeBc(ref gen: ArgsGenerator, exe: Exe) uni.Target
	{
		bcName := gen.genVoltBc(exe.name);
		return makeTargetExeGeneric(ref gen, exe, bcName, ArgsKind.VoltaBc);
	}

	fn makeTargetExeAr(ref gen: ArgsGenerator, exe: Exe) uni.Target
	{
		oName := gen.genVoltA(exe.name);
		return makeTargetExeGeneric(ref gen, exe, oName, ArgsKind.VoltaAr);
	}

	fn makeTargetExeO(ref gen: ArgsGenerator, exe: Exe) uni.Target
	{
		return makeHelperBitcodeToObj(ref gen, makeTargetExeBc(ref gen, exe));
	}

	fn makeTargetExe(ref gen: ArgsGenerator, exe: Exe) uni.Target
	{
		name := exe.bin is null ? exe.name : exe.bin;
		if (mGen.config.platform == Platform.MSVC && !endsWith(name, ".exe")) {
			name ~= ".exe";
		}

		t := ins.fileNoRule(name);

		// Add deps and return files to be added to arguments.
		fn cb(base: Project) string[] {
			return getStore(base.name, t);
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


	/*
	 *
	 * Other target functions.
	 *
	 */

	fn makeTargetC(ref gen: ArgsGenerator, src: string) uni.Target
	{
		oName := gen.genCO(src);

		t := ins.fileNoRule(oName);
		t.deps = [ins.file(src)];

		c := gen.config.ccCmd;
		assert(gen.config.ccKind == CCKind.Clang);

		t.rule = new uni.Rule();
		t.rule.cmd = c.cmd;
		t.rule.args = c.args ~ ["-o", oName, "-c", src];
		t.rule.print = c.print ~ oName;
		t.rule.outputs = [t];

		return t;
	}

	fn makeTargetAsm(ref gen: ArgsGenerator, src: string) uni.Target
	{
		obj := gen.genAsmO(src);

		tasm := ins.fileNoRule(obj);
		tasm.deps = [ins.file(src)];

		tasm.rule = new uni.Rule();
		tasm.rule.cmd = gen.config.nasmCmd.cmd;
		tasm.rule.args = gen.config.nasmCmd.args ~ [src, "-o", obj];
		tasm.rule.print = gen.config.nasmCmd.print ~ obj;
		tasm.rule.outputs = [tasm];

		return tasm;
	}

	fn makeHelperBitcodeToObj(ref gen: ArgsGenerator, bc: uni.Target) uni.Target
	{
		// Make o file.
		oName := gen.getFileOFromBC(bc.name);
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

	fn makeTargetVolted(ref gen: ArgsGenerator, exe: Exe) uni.Target
	{
		srcDir := exe.srcDir;
		mainFile := srcDir ~ dirSeparator ~ "main.d";
		name := gen.genVolted();

		t := ins.fileNoRule(name);
		t.rule = new uni.Rule();

		fn doScan(p: Project) string[] {
			files := deepScan(p.srcDir, ".d");
			deps := new uni.Target[](files.length);
			foreach (i, file; files) {
				deps[i] = ins.file(file);
			}
			t.deps ~= deps;
			return null;
		}

		c := gen.config.rdmdCmd;
		args := c.args ~ [
			"--build-only",
			"-of" ~ t.name
		];

		args ~= gen.genVoltArgs(exe, ArgsKind.Dmd, doScan);

		foreach (arg; exe.srcObj) {
			args ~= arg;
		}
		version (!Windows) {
			foreach (arg; exe.libPaths) {
				args ~= ("-L-L" ~ arg);
			}
			foreach (arg; exe.libs) {
				args ~= ("-L-l" ~ arg);
			}
		} else {
			foreach (arg; exe.libPaths) {
				args ~= ("-L/LIBPATH:" ~ arg);
			}
			foreach (arg; exe.libs) {
				args ~= ("-L" ~ arg);
			}	
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


private:
	fn addStore(name: string, store: Store)
	{
		if (store.bcs.length == 0 && store.objs.length == 0) {
			return;
		}

		mStore[name] = store;
	}

	fn getStore(name: string, t: uni.Target) string[]
	{
		r := name in mStore;
		if (r is null) {
			return null;
		}

		targets := r.bcs ~ r.objs;

		// Add the targets as dependancies.
		t.deps ~= targets;

		ret := new string[](targets.length);
		foreach (i, d; targets) {
			ret[i] = d.name;
		}
		return ret;
	}

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

class Store
{
public:
	uni.Target[] bcs;
	uni.Target[] objs;
}
