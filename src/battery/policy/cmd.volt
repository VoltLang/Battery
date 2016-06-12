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
 * Parser args and turns them into Libs and Exes.
 */
class ArgParser
{
public:
	Driver mDrv;
	Range mArgs;

	Lib[] mLibs;
	Exe[] mExes;

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

			mCurrent = scanDir(mDrv, tmp);
		}

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
				lib.srcDir = getNext("expected source folder");
				break;
			case "--dep":
				lib.deps ~= getNext("expected dependency");
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
				exe.srcC ~= tmp;
				continue;
			}

			if (endsWith(tmp, ".volt")) {
				exe.srcVolt ~= tmp;
				continue;
			}

			if (endsWith(tmp, ".o", ".obj")) {
				exe.srcObj ~= tmp;
				continue;
			}

			switch (tmp) {
			case "--name":
				exe.name = getNext("expected name");
				break;
			case "--src-I":
				exe.srcDir = getNext("expected source folder");
				break;
			case "-d", "-debug", "--debug":
				exe.isDebug = true;
				break;
			case "-D":
				exe.defs ~= getNext("expected define");
				break;
			case "--bin", "-o":
				exe.bin = getNext("expected binary file");
				break;
			case "--dep":
				exe.deps ~= getNext("expected dependency");
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
