// Copyright © 2016, Jakob Bornecrantz.  All rights reserved.
// See copyright notice in src/battery/license.volt (BOOST ver. 1.0).
/**
 * Holds code for parsing command line options into Lib and Exe.
 */
module battery.policy.cmd;

import watt.text.string : endsWith;

import battery.interfaces;
import battery.policy.dir;
import battery.policy.arg;


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
	Arg[] mArgs;
	size_t mPos;

	Lib[] mLibs;
	Exe[] mExes;


public:
	this(Driver drv)
	{
		mDrv = drv;
	}

	void parse(string[] args, out Lib[] libs, out Exe[] exes)
	{
		ToArgs toArgs;
		mPos = 0;
		mArgs = toArgs.process(mDrv, null, args);
		filterArgs(ref mArgs, mDrv.arch, mDrv.platform);

		for (; mPos < mArgs.length; mPos++) {
			parseDefault();
		}

		libs = mLibs;
		exes = mExes;
		mLibs = null;
		mExes = null;
	}

	void parse(string[] args, string path, Base base, out Lib[] libs, out Exe[] exes)
	{
		ToArgs toArgs;
		mPos = 0;
		mArgs = toArgs.process(mDrv, path, args);
		filterArgs(ref mArgs, mDrv.arch, mDrv.platform);

		process(base);

		libs = mLibs;
		exes = mExes;
		mLibs = null;
		mExes = null;
	}


protected:
	void parseDefault()
	{
		if (mPos >= mArgs.length) {
			return;
		}

		Base base;
		arg := mArgs[mPos++];
		switch (arg.kind) with (Arg.Kind) {
		case Exe: base = new Exe(); break;
		case Lib: base = new Lib(); break;
		case Directory: base = scanDir(mDrv, arg.extra); break;
		default: mDrv.abort("unknown argument '%s'", arg.flag);
		}

		process(base);
	}

	void process(Base base)
	{
		lib := cast(Lib)base;
		if (lib !is null) {
			parse(lib);
			verify(lib);
			mLibs ~= lib;
		}

		exe := cast(Exe)base;
		if (exe !is null) {
			parse(exe);
			verify(exe);
			mExes ~= exe;
		}
	}

	void parse(Lib lib)
	{
		for (; mPos < mArgs.length; mPos++) {
			arg := mArgs[mPos];
			switch (arg.kind) with (Arg.Kind) {
			case Name: lib.name = arg.extra; break;
			case SrcDir: lib.srcDir = arg.extra; break;
			case Dep: lib.deps ~= arg.extra; break;
			case Library: lib.libs ~= arg.extra; break;
			default:
				return parseDefault();
			}
		}
	}

	void parse(Exe exe)
	{
		for (; mPos < mArgs.length; mPos++) {
			arg := mArgs[mPos];
			switch (arg.kind) with (Arg.Kind) {
			case Name: exe.name = arg.extra; break;
			case SrcDir: exe.srcDir = arg.extra; break;
			case Dep: exe.deps ~= arg.extra; break;
			case Library: exe.libs ~= arg.extra; break;
			case Debug: exe.isDebug = true; break;
			case Output: exe.bin = arg.extra; break;
			case Identifier: exe.defs ~= arg.extra; break;
			case FileC: exe.srcC ~= arg.extra; break;
			case FileObj: exe.srcObj ~= arg.extra; break;
			case FileVolt: exe.srcVolt ~= arg.extra; break;
			default:
				return parseDefault();
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


struct ToArgs
{
	Arg[] process(Driver mDrv, string mPath, string[] args)
	{
		Range mArgs;
		mArgs.setup(args);

		ret : Arg[];

		condArch, condPlatform : int;

		void setCondP(Platform platform) {
			condPlatform |= 1 << platform;
		}

		void setCondA(Arch arch) {
			condArch |= 1 << arch;
		}

		string getNext(string error)
		{
			mArgs.popFront();
			if (!mArgs.empty()) {
				return mArgs.front();
			}

			mDrv.abort(error);
			assert(false);
		}

		void apply(Arg arg) {
			arg.condArch = condArch;
			arg.condPlatform = condPlatform;
			condArch = condPlatform = 0;
		}

		Arg arg(Arg.Kind kind) {
			a : Arg;
			ret ~= a = new Arg(kind, mArgs.front());
			apply(a);
			return a;
		}

		Arg argPath(Arg.Kind kind) {
			a := arg(kind);
			a.extra = mPath ~ a.flag;
			return a;
		}

		Arg argNext(Arg.Kind kind, string error) {
			a := arg(kind);
			a.extra = getNext(error);
			return a;
		}

		Arg argNextPath(Arg.Kind kind, string error) {
			a := argNext(kind, error);
			a.extra = mPath ~ a.extra;
			return a;
		}

		for (mArgs.setup(args); !mArgs.empty(); mArgs.popFront()) {
			tmp := mArgs.front();
			switch (tmp) with (Arg.Kind) {
			case "--exe": arg(Exe); continue;
			case "--lib": arg(Lib); continue;
			case "--name": argNext(Name, "expected name"); continue;
			case "--dep": argNext(Dep, "expected dependency"); continue;
			case "--src-I": argNextPath(SrcDir, "expected source directory"); continue;
			case "-l": argNext(Library, "expected library name"); continue;
			case "-L": argNext(LibraryPath, "expected library path"); continue;
			case "-d", "-debug", "--debug": arg(Debug); continue;
			case "--bin", "-o": argNextPath(Output, "expected binary file"); continue;
			case "-D": argNext(Identifier, "expected version identifier"); continue;
			case "--if-linux": setCondP(Platform.Linux); continue;
			case "--if-osx": setCondP(Platform.OSX); continue;
			case "--if-msvc": setCondP(Platform.MSVC); continue;
			case "--if-mingw": mDrv.abort("mingw platform not supported"); continue;
			case "--if-metal": mDrv.abort("metal platform not supported"); continue;
			case "--if-x86": setCondA(Arch.X86); continue;
			case "--if-x86_64": setCondA(Arch.X86_64); continue;
			case "--if-le32": mDrv.abort("le32 arch not supported"); continue;
			default:
			}

			if (endsWith(tmp, ".c")) {
				argPath(Arg.Kind.FileC);
			} else if (endsWith(tmp, ".volt")) {
				argPath(Arg.Kind.FileVolt);
			} else if (endsWith(tmp, ".o", ".obj", ".lib")) {
				argPath(Arg.Kind.FileObj);
			} else if (tmp[0] == '-') {
				mDrv.abort("unknown argument '%s'", tmp);
			} else {
				argPath(Arg.Kind.Directory);
			}
		}

		return ret;
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
