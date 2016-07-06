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


class Builder
{
public:
	Driver mDrv;

	Configuration config;

	Lib[] libs;
	Exe[] exes;

	Lib[string] store;

	string[] voltArgs;
	uni.Target mega;
	uni.Instance ins;

	string rtSrcDir;
	uni.Target rtBin;
	uni.Target voltaBin;

public:
	this(Driver drv)
	{
		this.mDrv = drv;
	}

	void build(Configuration config, string voltaDir, Lib[] libs, Exe[] exes)
	{
		this.config = config;
		this.libs = libs;
		this.exes = exes;
		this.ins = new uni.Instance();
		this.mega = ins.fileNoRule("__all");

		if (voltaDir is null) {
			voltaBin = ins.fileNoRule(config.volta.cmd);
			rtBin = ins.fileNoRule(config.volta.rtBin);
			rtSrcDir = config.volta.rtDir;
		} else {
			rtSrcDir = voltaDir ~ dirSeparator ~
				"rt" ~ dirSeparator ~ "src";
			voltaBin = makeTargetVolta(voltaDir);
			rtBin = makeTargetVoltLibrary("librt", rtSrcDir);
		}

		setupVoltArgs();

		// Make the libraries searchable.
		foreach (lib; libs) {
			store[lib.name] = lib;
		}

		// Generate rules for all the executables.
		foreach (exe; exes) {
			mega.deps ~= makeTargetExe(exe);
		}

		// Do the build.
		uni.build(mega, 4, config.env);
	}

	uni.Target makeTargetExe(Exe exe)
	{
		name := exe.bin is null ? exe.name : exe.bin;
		version (Windows) if (!endsWith(name, ".exe")) {
			name ~= ".exe";
		}
		dep := ".bin" ~ dirSeparator ~ name ~ ".d";

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
		args := voltArgs ~ collect(exe) ~
			["-o", name, "--dep", dep] ~ exe.srcVolt;

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
		t.rule.print = "  VOLTA    " ~ name;
		t.rule.args = args;
		t.rule.outputs = [t, d];

		return t;
	}

	uni.Target makeTargetC(string src)
	{
		obj := ".bin" ~ dirSeparator ~ src ~ ".o";

		tc := ins.fileNoRule(obj);
		tc.deps = [ins.file(src)];

		switch (config.cc.kind) with (CCompiler.Kind) {
		case GCC:
			tc.rule = new uni.Rule();
			tc.rule.cmd = config.cc.cmd;
			tc.rule.args = [src, "-c", "-o", obj];
			tc.rule.print = "  GCC      " ~ obj;
			tc.rule.outputs = [tc];
			break;
		case CL:
			tc.rule = new uni.Rule();
			tc.rule.cmd = config.cc.cmd;
			tc.rule.args = [src, "/c", "/Fo" ~ obj];
			tc.rule.print = "  MSVC     " ~ obj;
			tc.rule.outputs = [tc];
			break;
		default:
			mDrv.abort("unknown C compiler");
		}

		return tc;
	}

	uni.Target makeTargetVolta(string dir)
	{
		srcDir := dir ~ dirSeparator ~ "src";
		mainFile := srcDir ~ dirSeparator ~ "main.d";
		files := deepScan(mDrv, srcDir, ".d");
		name := ".bin" ~ dirSeparator ~ "volted";
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
			"--compiler=" ~ config.rdmd.dmd,
			"-I" ~ srcDir,
			"-of" ~ t.name
		];

		str := getOutput("llvm-config",
			["--system-libs",
			"--ldflags",
			"--libs",
			"core",
			"bitwriter",
			"bitreader",
			"linker",
			"target",
			"x86codegen",
			"engine"]);

		foreach (arg; parseArguments(str)) {
			args ~= ("-L" ~ arg);
		}
		args ~= "-L-lstdc++";
		args ~= mainFile;

		t.rule.outputs = [t];
		t.rule.cmd = config.rdmd.rdmd;
		t.rule.args = args;
		t.rule.print = "  RDMD     " ~ t.name;

		return t;
	}

	uni.Target makeTargetVoltLibrary(string name, string dir)
	{
		obj := ".bin" ~ dirSeparator ~ name ~ ".o";
		files := deepScan(mDrv, dir, ".volt");

		t := ins.fileNoRule(obj);
		t.deps = new uni.Target[](files.length);
		foreach (i, file; files) {
			t.deps[i] = ins.file(file);
		}

		args := ["--no-stdlib",
			"--platform", .toString(config.platform),
			"--arch", .toString(config.arch),
			"-c", "-o", obj] ~ files;

		// Depend on the compiler.
		t.deps ~= voltaBin;

		// Make the rule.
		t.rule = new uni.Rule();
		t.rule.cmd = voltaBin.name;
		t.rule.print = "  VOLTA    " ~ t.name;
		t.rule.args = args;
		t.rule.outputs = [t];

		return t;
	}

	string[] collect(Exe exe)
	{
		ret : string[];

		Base[string] added;
		void traverse(Base b)
		{
			// Has this dep allready been added.
			auto p = b.name in added;
			if (p !is null) {
				return;
			}

			ret ~= ["--src-I", b.srcDir];

			added[b.name] = b;

			foreach (path; b.libPaths) {
				ret ~= ["-L", path];
			}

			foreach (path; b.stringPaths) {
				ret ~= ["-J", path];
			}

			foreach (lib; b.libs) {
				ret ~= ["-l", lib];
			}

			foreach (def; b.defs) {
				ret ~= ["-D", def];
			}

			foreach (arg; b.xcc) {
				ret ~= ["--Xcc", arg];
			}

			foreach (arg; b.xlink) {
				ret ~= ["--Xlink", arg];
			}

			foreach (arg; b.xlinker) {
				ret ~= ["--Xlinker", arg];
			}

			foreach (dep; b.deps) {
				base := dep in store;
				traverse(*base);
			}
		}

		traverse(exe);

		// Set debug.
		if (exe.isDebug) {
			ret ~= "-d";
		}

		return ret;
	}

	void setupVoltArgs()
	{
		voltArgs = [
			"--no-stdlib",
			"--platform",
			.toString(config.platform),
			"--arch",
			.toString(config.arch),
			getLinkerFlag(config),
			config.linker.cmd,
			rtBin.name,
			"--lib-I",
			rtSrcDir,
		];

		foreach (lib; config.volta.rtLibs[config.platform]) {
			voltArgs ~= ["-l", lib];
		}
	}

	string getLinkerFlag(Configuration config)
	{
		final switch (config.linker.kind) {
		case Linker.Kind.LD: return "--ld";
		case Linker.Kind.GCC: return "--cc";
		case Linker.Kind.Link: return "--link";
		case Linker.Kind.Clang: return "--cc";
		}
	}
}
