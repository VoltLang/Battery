// Copyright © 2016, Jakob Bornecrantz.  All rights reserved.
// See copyright notice in src/battery/license.volt (BOOST ver. 1.0).
/**
 * Holds code for parsing command line options into Lib and Exe.
 */
module battery.policy.cmd;

import watt.text.string : endsWith;

import battery.interfaces;
import battery.policy.dir;


/**
 * Turn Libs and Exes into command line arguments.
 */
string[] getArgs(Lib[] libs, Exe[] exes)
{
	string[] ret;

	foreach (lib; libs) {
		ret ~= getArgsLib(lib);
	}

	foreach (exe; exes) {
		ret ~= getArgsExe(exe);
	}

	return ret;
}

string[] getArgsBase(Base b, string start)
{
	ret := ["#",
		"# " ~ b.name,
		start,
		"--name",
		b.name
	];

	foreach (dep; b.deps) {
		ret ~= ["--dep", dep];
	}

	if (b.bin !is null) {
		ret ~= ["-o", b.bin];
	}

	foreach (def; b.defs) {
		ret ~= ["-D", def];
	}

	foreach (lib; b.libs) {
		ret ~= ["-l", lib];
	}

	ret ~= ["--src-I", b.srcDir];

	return ret;
}

string[] getArgsLib(Lib l)
{
	return getArgsBase(l, "--lib");
}

string[] getArgsExe(Exe e)
{
	ret := getArgsBase(e, "--exe");

	if (e.isDebug) {
		ret ~= "-debug";
	}

	ret ~= e.srcC;
	ret ~= e.srcObj;
	ret ~= e.srcVolt;

	return ret;
}


/**
 * Parser args and turns them into Libs and Exes.
 */
class ArgParser
{
public:
	Driver mDrv;
	Range mArgs;

	Lib[] mLibs;
	Exe[] mExes;

	///< Additional path to add to files.
	string mPath;

	Base mCurrent;

public:
	this(Driver drv)
	{
		mDrv = drv;
	}

	void parse(string[] args, out Lib[] libs, out Exe[] exes)
	{
		for (mArgs.setup(args); !mArgs.empty(); mArgs.popFront()) {
			parseDefault(mArgs.front());
		}

		libs = mLibs;
		exes = mExes;
		mPath = null;
		mLibs = null;
		mExes = null;
		mCurrent = null;
	}

	void parse(string[] args, string path, Base lib, out Lib[] libs, out Exe[] exes)
	{
		mArgs.setup(args);
		mPath = path;
		mCurrent = lib;

		processCurrent();

		libs = mLibs;
		exes = mExes;
		mPath = null;
		mLibs = null;
		mExes = null;
		mCurrent = null;
	}

protected:
	string getNext(string error)
	{
		mArgs.popFront();
		if (!mArgs.empty()) {
			return mArgs.front();
		}

		mDrv.abort(error);
		assert(false);
	}

	void parseDefault(string tmp)
	{
		mArgs.popFront();

		switch (tmp) {
		case "--exe": mCurrent = new Exe(); break;
		case "--lib": mCurrent = new Lib(); break;
		default:
			if (tmp[0] == '-') {
				mDrv.abort("unknown argument '%s'", tmp);
			}

			mCurrent = scanDir(mDrv, mPath ~ tmp);
		}

		processCurrent();
	}

	void processCurrent()
	{
		lib := cast(Lib)mCurrent;
		if (lib !is null) {
			parse(lib);
			verify(lib);
			mLibs ~= lib;
		}

		exe := cast(Exe)mCurrent;
		if (exe !is null) {
			parse(exe);
			verify(exe);
			mExes ~= exe;
		}
	}

	void parse(Lib lib)
	{	
		for (; !mArgs.empty(); mArgs.popFront()) {
			tmp := mArgs.front();

			switch (tmp) {
			case "--name":
				lib.name = getNext("expected name");
				break;
			case "--src-I":
				lib.srcDir = mPath ~ getNext("expected source folder");
				break;
			case "--dep":
				lib.deps ~= getNext("expected dependency");
				break;
			case "-l":
				lib.libs ~= getNext("expected library name");
				break;
			default:
				return parseDefault(tmp);
			}
		}
	}

	void parse(Exe exe)
	{
		for (; !mArgs.empty(); mArgs.popFront()) {
			tmp := mArgs.front();

			if (endsWith(tmp, ".c")) {
				exe.srcC ~= mPath ~ tmp;
				continue;
			}

			if (endsWith(tmp, ".volt")) {
				exe.srcVolt ~= mPath ~ tmp;
				continue;
			}

			if (endsWith(tmp, ".o", ".obj")) {
				exe.srcObj ~= mPath ~ tmp;
				continue;
			}

			switch (tmp) {
			case "--name":
				exe.name = getNext("expected name");
				break;
			case "--src-I":
				exe.srcDir = mPath ~ getNext("expected source folder");
				break;
			case "--dep":
				exe.deps ~= getNext("expected dependency");
				break;
			case "-l":
				exe.libs ~= getNext("expected library name");
				break;
			case "-d", "-debug", "--debug":
				exe.isDebug = true;
				break;
			case "-D":
				exe.defs ~= getNext("expected define");
				break;
			case "--bin", "-o":
				exe.bin = mPath ~ getNext("expected binary file");
				break;
			default:
				return parseDefault(tmp);
			}
		}
	}

	void verify(Lib lib)
	{
		if (lib.name is null) {
			mDrv.abort("library not given a name '--name'");
		}

		if (lib.srcDir is null) {
			mDrv.abort("library not given a source directory '--src-I'");
		}
	}

	void verify(Exe exe)
	{
		if (exe.name is null) {
			mDrv.abort("executable not given a name '--name'");
		}

		if (exe.srcDir is null) {
			mDrv.abort("executable not given a source directory '--src-I'");
		}

		if (exe.bin is null) {
			mDrv.abort("executable not given a output file '-o'");
		}
	}
}


/**
 * In light of ranges in Volt.
 */
private struct Range
{
private:
	string[] mArgs;


public:
	void setup(string[] args)
	{
		mArgs = args;
	}


public:
	/*
	 *
	 * Range
	 *
	 */

	string front()
	{
		if (mArgs.length > 0) {
			return mArgs[0];
		} else {
			return null;
		}
	}

	void popFront()
	{
		if (mArgs.length > 1) {
			mArgs = mArgs[1 .. $];
		} else {
			mArgs = null;
		}
	}

	bool empty()
	{
		return mArgs.length == 0;
	}
}
