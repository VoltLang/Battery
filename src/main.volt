// Copyright © 2015-2016, Jakob Bornecrantz.  All rights reserved.
// See copyright notice in src/battery/license.volt (BOOST ver. 1.0).
module main;

import core.stdc.stdlib : exit;
import watt.io : writefln, error;
import watt.process : getEnv;
import watt.text.string : endsWith;
import watt.path : dirSeparator;

import uni = uni.core;

import battery.driver;
import battery.license;
import battery.interfaces;
import battery.configuration;
import battery.policy.host : getHostConfig;
import battery.policy.rt : getRtCompile;
import battery.backend.compile : buildCmd, Compile;


int main(string[] args)
{
	drv := new DefaultDriver();
	exes : Exe[];
	libs : Lib[];

	drv.process(args);
	drv.get(out libs, out exes);
	foreach (exe; exes) {
		doBuild(libs, exe);
	}

	return 0;
}

void doBuild(Lib[] libs, Exe exe)
{
	// Setup the build enviroment and configuration.
	path := getEnv("PATH");
	config := getHostConfig(path);
	vrt := getRtCompile(config);

	// Put all of the libraries in the store for lookup.
	store := new Store();
	foreach (lib; libs) {
		store.put(lib);
	}

	// Collect all of the deps, defs and various flags into compiles.
	c := collect(store, config, exe);
	c.deps = vrt ~ c.deps;

	// Turn the Compile into a command line.
	ret := buildCmd(config, c);

	// Feed that into the solver and have it solve it for us.
	ins := new uni.Instance();
	t := ins.fileNoRule(c.derivedTarget);
	t.deps = new uni.Target[](c.src.length);

	foreach (i, src; c.src) {
		t.deps[i] = ins.file(src);
	}

	foreach (src; exe.srcC) {
		obj := makeTargetC(config, ins, src);
		t.deps ~= obj;
		ret ~= obj.name;
	}

	t.rule = new uni.Rule();
	t.rule.cmd = ret[0];
	t.rule.print = "  VOLTA    " ~ c.derivedTarget;
	t.rule.args = ret[1 .. $];

	uni.build(t, 2);
}

uni.Target makeTargetC(Configuration config, uni.Instance ins, string src)
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
		abort("unknown C compiler");
	}

	return tc;
}

Compile collect(Store store, Configuration config, Exe exe)
{

	// Set debug.
	config.isDebug = exe.isDebug;

	Compile[string] added;
	Compile traverse(Base b, Compile c = null)
	{
		// Has this dep allready been added.
		auto p = b.name in added;
		if (p !is null) {
			return *p;
		}

		if (c is null) {
			lib := cast(Lib)b;
			c = libToCompile(lib);
		}
		added[b.name] = c;

		foreach (def; b.defs) {
			config.defs ~= def;
		}

		foreach (dep; b.deps) {
			base := store.get(dep);
			c.deps ~= traverse(store.get(dep));
		}

		return c;
	}

	return traverse(exe, exeToCompile(exe));
}

void printLicense()
{
	foreach (l; licenseArray) {
		writefln(l);
	}
}

Compile libToCompile(Lib lib)
{
	c := new Compile();
	c.library = true;
	c.name = lib.name;
	c.srcRoot = lib.srcDir;
	c.libs = lib.libs;

	return c;
}

Compile exeToCompile(Exe exe)
{
	c := new Compile();
	c.name = exe.name;
	c.srcRoot = exe.srcDir;
	c.libs = exe.libs;
	c.src = exe.srcVolt ~ exe.srcObj;
	c.derivedTarget = exe.bin is null ? exe.name : exe.bin;
	version (Windows) if (!endsWith(c.derivedTarget, ".exe")) {
		c.derivedTarget ~= ".exe";
	}
	return c;
}

class Store
{
private:
	Base[string] mStore;

public:
	Base get(string v)
	{
		assert(v !is null);
		auto r = v in mStore;
		if (r is null) {
			abort("'" ~ v ~ "' not defined as lib or exe");
		}
		return *r;
	}

	void put(Base b)
	{
		assert(b.name !is null);
		if ((b.name in mStore) !is null) {
			abort("'" ~ b.name ~ "' already added");
		}
		mStore[b.name] = b;
	}
}

/**
 * Print message and abort.
 */
void abort(string msg)
{
	error.writefln("battery: " ~ msg);
	exit(-1);
}
