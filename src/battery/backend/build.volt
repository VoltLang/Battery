// Copyright © 2016, Jakob Bornecrantz.  All rights reserved.
// See copyright notice in src/battery/license.volt (BOOST ver. 1.0).
module battery.backend.build;

import watt.text.string : endsWith;
import watt.path : dirSeparator;

import uni = uni.core;
import battery.interfaces;
import battery.configuration;


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
		uni.build(mega, 4);
	}

	uni.Target makeTargetExe(Exe exe)
	{
		name := exe.bin is null ? exe.name : exe.bin;
		version (Windows) if (!endsWith(name, ".exe")) {
			name ~= ".exe";
		}

		t := ins.fileNoRule(name);
		t.deps = new uni.Target[](exe.srcVolt.length);

		// Do dependancy tracking on source.
		foreach (i, src; exe.srcVolt) {
			t.deps[i] = ins.file(src);
		}

		// Get all of the arguments.
		args := voltArgs ~ collect(exe) ~
			["-o", name] ~ exe.srcVolt;

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

		// Make the rule.
		t.rule = new uni.Rule();
		t.rule.cmd = config.volta.cmd;
		t.rule.print = "  VOLTA    " ~ name;
		t.rule.args = args;

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
			break;
		case CL:
			tc.rule = new uni.Rule();
			tc.rule.cmd = config.cc.cmd;
			tc.rule.args = [src, "/c", "/Fo" ~ obj];
			tc.rule.print = "  MSVC     " ~ obj;
			break;
		default:
			mDrv.abort("unknown C compiler");
		}

		return tc;
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

			foreach (def; b.defs) {
				ret ~= ["-D", def];
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
			config.linker.flag,
			config.linker.cmd,
			config.volta.rtBin,
			"--lib-I",
			config.volta.rtDir
		];

		foreach (lib; config.volta.rtLibs[config.platform]) {
			voltArgs ~= ["-l", lib];
		}
	}
}
