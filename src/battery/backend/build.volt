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

	string archStr;
	string platformStr;

	string buildDir;

	uni.Target mega;
	uni.Instance ins;

	string gccPrint   = "  GCC      ";
	string rdmdPrint  = "  RDMD     ";
	string msvcPrint  = "  MSVC     ";
	string voltaPrint = "  VOLTA    ";

	Exe voltaExe;
	string[] voltaArgs;
	uni.Target voltaBin;
	uni.Target voltedBin;

	Lib rtLib;
	uni.Target rtBin;

public:
	this(Driver drv)
	{
		this.mDrv = drv;
	}

	void build(Configuration config, Lib[] libs, Exe[] exes)
	{
		this.config = config;
		this.libs = libs;
		this.exes = exes;
		this.ins = new uni.Instance();
		this.mega = ins.fileNoRule("__all");
		this.archStr = .toString(config.arch);
		this.platformStr = .toString(config.platform);
		this.buildDir = ".bin" ~ dirSeparator ~ archStr ~ "-" ~
			platformStr;

		// Make the libraries searchable.
		foreach (lib; libs) {
			store[lib.name] = lib;
		}

		setupVolta(ref exes);
		setupVoltaArgs();

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
		args := voltaArgs ~ collect(exe) ~
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
		t.rule.print = voltaPrint ~ name;
		t.rule.args = args;
		t.rule.outputs = [t, d];

		return t;
	}

	uni.Target makeTargetC(string src)
	{
		obj := buildDir ~ dirSeparator ~ src ~ ".o";

		tc := ins.fileNoRule(obj);
		tc.deps = [ins.file(src)];

		switch (config.cc.kind) with (CCompiler.Kind) {
		case GCC:
			tc.rule = new uni.Rule();
			tc.rule.cmd = config.cc.cmd;
			tc.rule.args = [src, "-c", "-o", obj];
			tc.rule.print = gccPrint ~ obj;
			tc.rule.outputs = [tc];
			break;
		case CL:
			tc.rule = new uni.Rule();
			tc.rule.cmd = config.cc.cmd;
			tc.rule.args = [src, "/c", "/Fo" ~ obj];
			tc.rule.print = msvcPrint ~ obj;
			tc.rule.outputs = [tc];
			break;
		default:
			mDrv.abort("unknown C compiler");
		}

		return tc;
	}

	uni.Target makeTargetVolted()
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
			"--compiler=" ~ config.rdmd.dmd,
			"-I" ~ srcDir,
			"-of" ~ t.name
		];

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
		t.rule.cmd = config.rdmd.rdmd;
		t.rule.args = args;
		t.rule.print = rdmdPrint ~ t.name;

		return t;
	}

	uni.Target makeTargetVoltLibrary(Lib lib)
	{
		lib.bin = buildDir ~ dirSeparator ~ lib.name ~ ".o";
		files := deepScan(mDrv, lib.srcDir, ".volt");

		t := ins.fileNoRule(lib.bin);
		t.deps = new uni.Target[](files.length);
		foreach (i, file; files) {
			t.deps[i] = ins.file(file);
		}

		args := ["--no-stdlib",
			"--arch", archStr,
			"--platform", platformStr,
			"-c", "-o", lib.bin] ~ files;

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

	string[] collect(Exe exe)
	{
		ret : string[];

		Base[string] added;
		void traverse(Base b, bool first = false)
		{
			// Has this dep allready been added.
			auto p = b.name in added;
			if (p !is null) {
				return;
			}

			if (first || b.bin is null) {
				ret ~= ["--src-I", b.srcDir];
			} else {
				ret ~= b.bin;
				ret ~= ["--lib-I", b.srcDir];
			}

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

		traverse(exe, true);

		// Implictly add rt as a dependancy
		traverse(rtLib);

		// Set debug.
		if (exe.isDebug) {
			ret ~= "-d";
		}

		return ret;
	}

	void setupVolta(ref Exe[] exes)
	{
		// Filter out the volta exe.
		pos : size_t;
		foreach (i, exe; exes) {
			if (exe.name == "volta") {
				voltaExe = exe;
				continue;
			}
			exes[pos++] = exe;
		}
		if (voltaExe !is null) {
			exes = exes[0 .. $-1];
		}

		// Assume driver have checked that it exsits.
		rtLib = store["rt"];

		voltaBin = voltedBin = makeTargetVolted();
		rtBin = makeTargetVoltLibrary(rtLib);
	}

	void setupVoltaArgs()
	{
		voltaArgs = [
			"--no-stdlib",
			"--platform", platformStr,
			"--arch", archStr,
			getLinkerFlag(config),
			config.linker.cmd,
		];
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
