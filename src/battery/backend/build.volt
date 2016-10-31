// Copyright © 2016, Jakob Bornecrantz.  All rights reserved.
// See copyright notice in src/battery/license.volt (BOOST ver. 1.0).
module battery.backend.build;

import core.exception;
import watt.text.string : endsWith;
import watt.process;
import watt.path : dirSeparator;

import uni = uni.core;
import uni.util.make;

import battery.interfaces;
import battery.configuration;
import battery.backend.command;
import battery.frontend.dir : deepScan;

import watt.io;


class Builder
{
public:
	mDrv: Driver;

	config: Configuration;

	buildDir: string;

	mega: uni.Target;
	ins: uni.Instance;

	voltaPrint: string = "  VOLTA    ";

	voltaExe: Exe;
	teslaExe: Exe;
	/// TODO remove once Volta can build bitcode without rt.
	rtLib: Lib;

	voltaBin: uni.Target;
	voltedBin: uni.Target;
	teslaBin: uni.Target;

	gen: ArgsGenerator;


protected:
	/// Store of objects each Lib/Exe produces.
	mObjs: uni.Target[][string];


public:
	this(Driver drv)
	{
		this.mDrv = drv;
	}

	fn build(config: Configuration, libs: Lib[], exes: Exe[])
	{
		this.config = config;
		this.ins = new uni.Instance();
		this.mega = ins.fileNoRule("__all");

		gen.setup(config, libs, exes);

		this.buildDir = ".bin" ~ dirSeparator ~
			gen.archStr ~ "-" ~ gen.platformStr;

		filterExes(ref exes);

		// Setup volta and rtLib.
		voltaBin = voltedBin = makeTargetVolted();
		mega.deps = [voltaBin];
		rtLib = cast(Lib)gen.store["rt"];

		// Make sure each library is built.
		foreach (lib; libs) {
			mega.deps ~= makeTargetVoltLibrary(lib);
		}

		// If Volta was given, add it as well.
		if (false && voltaExe !is null) {
			mega.deps ~= makeTargetExe(voltaExe);
		}

		// If Tesla was given, add it as well.
		if (teslaExe !is null) {
			teslaBin = makeTargetExe(teslaExe);
			mega.deps ~= teslaBin;
		}

		// Generate rules for all the executables.
		foreach (exe; exes) {
			mega.deps ~= makeTargetExe(exe);
		}

		// Do the build.
		try {
			uni.build(mega, 8, config.env);
		} catch (Exception e) {
			mDrv.abort(e.msg);
		}
	}

	fn makeTargetExeBc(exe: Exe) uni.Target
	{
		bcName := buildDir ~ dirSeparator ~ exe.name ~ ".bc";
		depName := buildDir ~ dirSeparator ~ exe.name ~ ".d";

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
		args := gen.genVoltaArgs(exe) ~
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

	fn makeTargetExe(exe: Exe) uni.Target
	{
		oName := buildDir ~ dirSeparator ~ exe.name ~ ".o";

		// Build bitcode and object
		bc := makeTargetExeBc(exe);
		o := makeHelperBitcodeToObj(bc, oName);

		// Flatten the dep graph.
		mega.deps ~= bc;

		// For the bitcode file and extra inputs.
		aux : uni.Target[] = [o];

		// Setup C targets.
		foreach (src; exe.srcC) {
			aux ~= makeTargetC(src);
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
		version (Windows) if (!endsWith(name, ".exe")) {
			name ~= ".exe";
		}

		t := ins.fileNoRule(name);
		args := gen.genVoltaArgs(exe) ~ ["-o", name];

		// Add objects from libraries.
		targetDeps := collectDeps(base:exe);
		t.deps ~= targetDeps;
		foreach (tDep; targetDeps) {
			args ~= tDep.name;
		}

		// Make the rule.
		t.rule = new uni.Rule();
		t.rule.cmd = voltaBin.name;
		t.rule.print = voltaPrint ~ t.name;
		t.rule.args = args;
		t.rule.outputs = [t];

		return t;
	}

	fn makeTargetC(src: string) uni.Target
	{
		obj := buildDir ~ dirSeparator ~ src ~ ".o";

		tc := ins.fileNoRule(obj);
		tc.deps = [ins.file(src)];

		c := config.ccCmd;
		final switch (config.ccKind) with (CCKind) {
		case GCC, Clang:
			tc.rule = new uni.Rule();
			tc.rule.cmd = c.cmd;
			tc.rule.args = c.args ~ [src, "-c", "-o", obj];
			tc.rule.print = c.print ~ obj;
			tc.rule.outputs = [tc];
			break;
		case CL:
			tc.rule = new uni.Rule();
			tc.rule.cmd = c.cmd;
			tc.rule.args = c.args ~ [src, "/c", "/Fo" ~ obj];
			tc.rule.print = c.print ~ obj;
			tc.rule.outputs = [tc];
			break;
		case Invalid: assert(false);
		}

		return tc;
	}

	fn makeTargetAsm(src: string) uni.Target
	{
		obj := buildDir ~ dirSeparator ~ src ~ ".o";

		tasm := ins.fileNoRule(obj);
		tasm.deps = [ins.file(src)];

		tasm.rule = new uni.Rule();
		tasm.rule.cmd = config.nasmCmd.cmd;
		tasm.rule.args = config.nasmCmd.args ~ [src, "-o", obj];
		tasm.rule.print = config.nasmCmd.print ~ obj;
		tasm.rule.outputs = [tasm];

		return tasm;
	}

	fn makeTargetVolted() uni.Target
	{
		srcDir := voltaExe.srcDir;
		mainFile := srcDir ~ dirSeparator ~ "main.d";
		files := deepScan(mDrv, srcDir, ".d");
		name := buildDir ~ dirSeparator ~ "volted";
		version (Windows) if (!endsWith(name, ".exe")) {
			name ~= ".exe";
		}

		t := ins.fileNoRule(name);
		t.deps = new uni.Target[](files.length);
		foreach (i, file; files) {
			t.deps[i] = ins.file(file);
		}

		t.rule = new uni.Rule();

		c := config.rdmdCmd;

		args := c.args ~ [
			"--build-only",
			"-I" ~ srcDir,
			"-of" ~ t.name
		];

		foreach (arg; voltaExe.srcObj) {
			args ~= arg;
		}
		foreach (arg; voltaExe.libPaths) {
			args ~= ("-L-L" ~ arg);
		}
		foreach (arg; voltaExe.libs) {
			args ~= ("-L-l" ~ arg);
		}
		foreach (arg; voltaExe.xlinker) {
			args ~= ("-L" ~ arg);
		}
		args ~= mainFile;

		t.rule.outputs = [t];
		t.rule.cmd = c.cmd;
		t.rule.args = args;
		t.rule.print = c.print ~ t.name;

		return t;
	}

	fn makeTargetVoltLibrary(lib: Lib) uni.Target
	{
		files := deepScan(mDrv, lib.srcDir, ".volt");
		base := buildDir ~ dirSeparator ~ lib.name;
		bcName := base ~ ".bc";
		oName := base ~ ".o";

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
		bc.rule.args = gen.genVoltaArgs(lib) ~
			["-o", bcName, "-c", "--emit-bitcode"] ~ files;

		// Create the object file for the library.
		o := makeHelperBitcodeToObj(bc, oName);

		// Add results into into the store.
		results := [o];
		foreach (a; lib.srcAsm) {
			results ~= makeTargetAsm(a);
		}

		mObjs[lib.name] = results;

		return o;
	}

	fn makeHelperBitcodeToObj(bc: uni.Target, oName: string) uni.Target
	{
		// Make o file.
		o := ins.fileNoRule(oName);

		// Depend on the compiler and bitcode file.
		o.deps = [voltaBin, bc];

		// Make the rule.
		o.rule = new uni.Rule();
		o.rule.cmd = voltaBin.name;
		o.rule.print = voltaPrint ~ oName;
		o.rule.outputs = [o];
		o.rule.args = gen.voltaArgs ~
			["--lib-I", rtLib.srcDir] ~
			["-o", oName, "-c", bc.name];

		return o;
	}


private:
	fn collectDeps(base: Base) uni.Target[]
	{
		added: Base[string];
		ret: uni.Target[];

		fn traverse(b: Base)
		{
			// Has this dep allready been added.
			p := b.name in added;
			if (p !is null) {
				return;
			}

			// Keep track of it now.
			added[b.name] = b;

			r := b.name in mObjs;
			if (r !is null) {
				ret ~= *r;
			}

			foreach (dep; b.deps) {
				traverse(gen.store[dep]);
			}
		}

		traverse(base);

		// Implictly add rt as a dependancy
		traverse(gen.store["rt"]);

		return ret;
	}

	/**
	 * Filters out and sets the voltaExe and teslaExe files.
	 */
	fn filterExes(ref exes: Exe[])
	{
		// Always copy, so we don't modify the origanal storage.
		exes = new exes[..];
		
		pos : size_t;
		foreach (i, exe; exes) {
			switch (exe.name) {
			case "volta": voltaExe = exe; continue;
			case "tesla": teslaExe = exe; continue;
			default: exes[pos++] = exe; continue;
			}
		}
		exes = exes[0 .. pos];
	}
}
