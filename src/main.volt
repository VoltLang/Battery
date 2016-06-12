// Copyright © 2015-2016, Jakob Bornecrantz.  All rights reserved.
// See copyright notice in src/battery/license.volt (BOOST ver. 1.0).
module main;

import core.stdc.stdlib : exit;
import watt.io : writefln, error;
import watt.process : getEnv;
import watt.text.string : endsWith;

import uni = uni.core;

import battery.driver;
import battery.license;
import battery.compile;
import battery.interfaces;
import battery.configuration;
import battery.policy.host : getHostConfig;
import battery.policy.rt : getRtCompile;


int main(string[] args)
{
	if (args.length > 1 &&
	    (args[1] == "config" ||
	     args[1] == "build")) {
		drv := new DefaultDriver();
		exes : Exe[];
		libs : Lib[];

		ret := drv.process(args);
		if (ret != 0) {
			return ret;
		}

		drv.get(out libs, out exes);

		foreach (exe; exes) {
			doBuild(libs, exe);
		}

		return 0;
	}

	ArgParser p;
	ret := p.parse(args);
	if (ret) {
		return ret;
	}

	if (p.exe is null) {
		abort("must call with --exe");
	}
	doBuild(p.libs, p.exe);

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

	t.rule = new uni.Rule();
	t.rule.cmd = ret[0];
	t.rule.print = "  VOLTA  " ~ c.derivedTarget;
	t.rule.args = ret[1 .. $];

	uni.build(t, 2);
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

	return c;
}

Compile exeToCompile(Exe exe)
{
	c := new Compile();
	c.name = exe.name;
	c.srcRoot = exe.srcDir;
	c.src = exe.srcVolt ~ exe.srcObj;
	c.derivedTarget = exe.bin is null ? exe.name : exe.bin;
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



struct ArgParser
{
public:
	Lib[] libs;
	Exe exe;


private:
	string[] mArgs;
	size_t mPos;


public:
	/*
	 *
	 * Range
	 *
	 */

	string front()
	{
		return mArgs[mPos];
	}

	void popFront()
	{
		mPos += mPos < mArgs.length;
	}

	bool empty()
	{
		return mPos >= mArgs.length;
	}
}


/*
 *
 * Parsing functions.
 *
 */

int parse(ref ArgParser ap, string[] args)
{
	ap.mPos = 0;
	ap.mArgs = args;

	for (ap.popFront(); !ap.empty(); ap.popFront()) {
		ap.parseDefault(ap.front());
	}

	return 0;
}

string getNext(ref ArgParser ap, string error)
{
	if (!ap.empty()) {
		ap.popFront();
		return ap.front();
	}

	abort(error);
	assert(false);
}

void parseDefault(ref ArgParser ap, string tmp)
{
	switch (tmp) {
	case "--license":
		return printLicense();
	case "--exe":
		return ap.parseExe();
	case "--lib":
		return ap.parseLib();
	default:
		abort("unknown argument '" ~ tmp ~ "'");
	}
}

void parseLib(ref ArgParser ap)
{
	lib := new Lib();
	lib.name = ap.getNext("expected library name");
	ap.libs ~= lib;

	for (ap.popFront(); !ap.empty(); ap.popFront()) {
		tmp := ap.front();
		switch (tmp) {
		case "--src-I":
			lib.srcDir = ap.getNext("expected source folder");
			break;
		case "--bin":
			lib.bin = ap.getNext("expected binary file");
			break;
		case "--dep":
			lib.deps ~= ap.getNext("expected dependency");
			break;
		default:
			return ap.parseDefault(ap.front());
		}
	}
}

void parseExe(ref ArgParser ap)
{
	exe := new Exe();
	exe.name = ap.getNext("expected exe name");
	ap.exe = exe;

	for (ap.popFront(); !ap.empty(); ap.popFront()) {
		tmp := ap.front();

		if (endsWith(tmp, ".volt")) {
			exe.srcVolt ~= tmp;
			continue;
		}

		if (endsWith(tmp, ".obj")) {
			exe.srcObj ~= tmp;
			continue;
		}

		switch (tmp) {
		case "-d", "-debug", "--debug":
			exe.isDebug = true;
			break;
		case "-D":
			exe.defs ~= ap.getNext("expected define");
			break;
		case "--src-I":
			exe.srcDir = ap.getNext("expected source folder");
			break;
		case "--bin", "-o":
			exe.bin = ap.getNext("expected binary file");
			break;
		case "--dep":
			exe.deps ~= ap.getNext("expected dependency");
			break;
		default:
			return ap.parseDefault(ap.front());
		}
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
