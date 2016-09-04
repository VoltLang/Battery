// Copyright © 2016, Jakob Bornecrantz.  All rights reserved.
// See copyright notice in src/battery/license.volt (BOOST ver. 1.0).
module battery.backend.build;

import watt.text.string : endsWith;
import watt.process;
import watt.path : dirSeparator;

import uni = uni.core;
import uni.util.make;

import battery.interfaces;
import battery.configuration;
import battery.policy.dir;
import battery.backend.command;


class Builder
{
public:
	Driver mDrv;

	Configuration config;

	string buildDir;

	uni.Target mega;
	uni.Instance ins;

	string gccPrint   = "  GCC      ";
	string rdmdPrint  = "  RDMD     ";
	string msvcPrint  = "  MSVC     ";
	string voltaPrint = "  VOLTA    ";

	Exe voltaExe;
	Exe teslaExe;
	Lib rtLib;

	uni.Target voltaBin;
	uni.Target voltedBin;
	uni.Target rtBin;

	uni.Target teslaBin;

	ArgsGenerator gen;


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
		filterLibs(ref libs);

		// Setup volta and rtBin.
		voltaBin = voltedBin = makeTargetVolted();
		rtBin = makeTargetVoltLibrary(rtLib);
		mega.deps = [voltaBin, rtBin];

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
		uni.build(mega, 4, config.env);
	}

	fn makeTargetExe(exe: Exe) uni.Target
	{
		name := exe.bin is null ? exe.name : exe.bin;
		version (Windows) if (!endsWith(name, ".exe")) {
			name ~= ".exe";
		}
		dep := buildDir ~ dirSeparator ~ name ~ ".d";

		t := ins.fileNoRule(name);
		d := ins.file(dep);
		t.deps = new uni.Target[](exe.srcVolt.length);

		// Do dependancy tracking on source.
		foreach (i, src; exe.srcVolt) {
			t.deps[i] = ins.file(src);
		}

		// Depend on the compiler and runtime.
		t.deps ~= [voltaBin, rtBin];

		// Get all of the arguments.
		args := gen.genVoltaArgs(exe) ~
			["-o", name, "--dep", dep] ~
			exe.srcVolt;

		// Setup C targets.
		foreach (src; exe.srcC) {
			obj := makeTargetC(src);
			t.deps ~= obj;
			args ~= obj.name;
		}

		// Add additional object and library files.
		foreach (obj; exe.srcObj) {
			t.deps ~= ins.file(obj);
			args ~= obj;
		}

		importDepFile(ins, dep);

		// Make the rule.
		t.rule = new uni.Rule();
		t.rule.cmd = voltaBin.name;
		t.rule.print = voltaPrint ~ name;
		t.rule.args = args;
		t.rule.outputs = [t, d];

		return t;
	}

	fn makeTargetC(src: string) uni.Target
	{
		obj := buildDir ~ dirSeparator ~ src ~ ".o";

		tc := ins.fileNoRule(obj);
		tc.deps = [ins.file(src)];

		switch (config.ccKind) with (CCKind) {
		case GCC:
			tc.rule = new uni.Rule();
			tc.rule.cmd = config.ccCmd;
			tc.rule.args = [src, "-c", "-o", obj];
			tc.rule.print = gccPrint ~ obj;
			tc.rule.outputs = [tc];
			break;
		case CL:
			tc.rule = new uni.Rule();
			tc.rule.cmd = config.ccCmd;
			tc.rule.args = [src, "/c", "/Fo" ~ obj];
			tc.rule.print = msvcPrint ~ obj;
			tc.rule.outputs = [tc];
			break;
		default:
			mDrv.abort("unknown C compiler");
		}

		return tc;
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

		args := [
			"--build-only",
			"-I" ~ srcDir,
			"-of" ~ t.name
		];

		final switch (config.arch) with (Arch) {
		case X86: args ~= "-m32"; break;
		case X86_64: args ~= "-m64"; break;
		}

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
		t.rule.cmd = config.rdmdCmd;
		t.rule.args = args;
		t.rule.print = rdmdPrint ~ t.name;

		return t;
	}

	fn makeTargetVoltLibrary(lib: Lib) uni.Target
	{
		lib.bin = buildDir ~ dirSeparator ~ lib.name ~ ".o";
		files := deepScan(mDrv, lib.srcDir, ".volt");

		t := ins.fileNoRule(lib.bin);
		t.deps = new uni.Target[](files.length);
		foreach (i, file; files) {
			t.deps[i] = ins.file(file);
		}

		args := gen.genVoltaArgs(lib) ~
			["-o", lib.bin, "-c"] ~ files;

		// Depend on the compiler.
		t.deps ~= voltaBin;

		// Make the rule.
		t.rule = new uni.Rule();
		t.rule.cmd = voltaBin.name;
		t.rule.print = voltaPrint ~ t.name;
		t.rule.args = args;
		t.rule.outputs = [t];

		return t;
	}


private:
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

	/**
	 * Filter out and sets the rtLib files.
	 */
	fn filterLibs(ref libs: Lib[])
	{
		// Always copy, so we don't modify the origanal storage.
		libs = new libs[..];

		pos: size_t;
		foreach (i, lib; libs) {
			switch (lib.name) {
			case "rt": rtLib = lib; continue;
			default: libs[pos++] = lib; continue;
			}	
		}
		libs = libs[0 .. pos];
	}
}
