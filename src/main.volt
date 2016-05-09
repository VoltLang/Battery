// Copyright © 2015-2016, Jakob Bornecrantz.  All rights reserved.
// See copyright notice in src/battery/license.volt (BOOST ver. 1.0).
module main;

import watt.io : writefln;
import watt.process : getEnv;

import uni = uni.core;

import battery.license;
import battery.compile;
import battery.configuration;
import battery.policy.host : getHostConfig;
import battery.policy.rt : getRtCompile;


int main(string[] args)
{
	ArgParser p;
	auto ret = p.parse(args);
	if (ret) {
		return ret;
	}

	if (p.exe is null) {
		writefln("must call with --exe");
		return -1;
	}
	doBuild(p.libs, p.exe);

	return 0;
}

void doBuild(Lib[] libs, Exe exe)
{
	// Setup the build enviroment and configuration.
	auto path = getEnv("PATH");
	auto config = getHostConfig(path);
	auto vrt = getRtCompile(config);


	// Transforms Lib and Exe into compiles.
	Compile[string] store;
	foreach (lib; libs) {
		store[lib.name] = libToCompile(lib);
	}

	foreach (lib; store.values) {
		foreach (dep; exe.dep) {
			lib.deps ~= *(dep in store);
		}
	}

	auto c = exeToCompile(exe);
	c.deps = [vrt];
	foreach (dep; exe.dep) {
		c.deps ~= *(dep in store);
	}


	// Turn the Compile into a command line.
	auto ret = buildCmd(config, c);


	// Feed that into the solver and have it solve it for us.
	auto ins = new uni.Instance();
	auto t = ins.fileNoRule(c.derivedTarget);
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

void printLicense()
{
	foreach (l; licenseArray) {
		writefln(l);
	}
}

Compile libToCompile(Lib lib)
{
	auto c = new Compile();
	c.library = true;
	c.name = lib.name;
	c.srcRoot = lib.srcDir;

	return c;
}

Compile exeToCompile(Exe exe)
{
	auto c = new Compile();
	c.name = exe.name;
	c.srcRoot = exe.srcDir;
	c.src = exe.src;
	c.derivedTarget = exe.bin is null ? exe.name : exe.bin;
	return c;
}

class Base
{
	string name;
	string bin;

	string[] dep;

	string srcDir;
}

class Lib : Base
{

}

class Exe : Base
{
	string[] src;
}

struct ArgParser
{
public:
	Lib[] libs;
	Exe exe;

	enum Continue = 0;
	enum Stop = 1;
	enum Abort = 2;


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

	bool isEmpty()
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

	for (ap.popFront(); !ap.isEmpty(); ap.popFront()) {
		auto ret = ap.parseDefault(ap.front());
		if (ret == ArgParser.Abort) {
			return -1;
		}
	}

	return 0;
}

string getNext(ref ArgParser ap, string error)
{
	if (!ap.isEmpty()) {
		ap.popFront();
		return ap.front();
	}

	throw new Exception(error);
}

int parseDefault(ref ArgParser ap, string tmp)
{
	switch (tmp) {
	case "--license":
		printLicense();
		return ArgParser.Abort;
	case "--exe":
		return ap.parseExe();
	case "--lib":
		return ap.parseLib();
	default:
		writefln("unknown argument '%s'", tmp);
		return ArgParser.Abort;
	}
}

int parseLib(ref ArgParser ap)
{
	auto lib = new Lib();
	lib.name = ap.getNext("expected library name");
	ap.libs ~= lib;

	for (ap.popFront(); !ap.isEmpty(); ap.popFront()) {
		auto tmp = ap.front();
		switch (tmp) {
		case "-I":
			lib.srcDir = ap.getNext("expected source folder");
			break;
		case "--bin":
			lib.bin = ap.getNext("expected binary file");
			break;
		case "--dep":
			lib.dep ~= ap.getNext("expected dependency");
			break;
		default:
			auto ret = ap.parseDefault(ap.front());
			if (ret) {
				return ret;
			}
		}
	}

	return ArgParser.Stop;
}

int parseExe(ref ArgParser ap)
{
	auto exe = new Exe();
	exe.name = ap.getNext("expected exe name");
	ap.exe = exe;

	for (ap.popFront(); !ap.isEmpty(); ap.popFront()) {
		auto tmp = ap.front();

		if (tmp.length > 5 && tmp[$ - 5 .. $] == ".volt") {
			exe.src ~= tmp;
			continue;
		}

		switch (tmp) {
		case "-I":
			exe.srcDir = ap.getNext("expected source folder");
			break;
		case "--bin":
			exe.bin = ap.getNext("expected binary file");
			break;
		case "--dep":
			exe.dep ~= ap.getNext("expected dependency");
			break;
		default:
			auto ret = ap.parseDefault(ap.front());
			if (ret) {
				return ret;
			}
		}
	}

	return ArgParser.Stop;
}
