// Copyright © 2016, Jakob Bornecrantz.  All rights reserved.
// See copyright notice in src/battery/license.volt (BOOST ver. 1.0).
/**
 * Holds code for parsing command line options into Lib and Exe.
 */
module battery.policy.cmd;

import watt.process;
import watt.text.path : normalizePath;
import watt.text.string : startsWith, endsWith;

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

	foreach (path; b.libPaths) {
		ret ~= ["-L", path];
	}

	foreach (path; b.stringPaths) {
		ret ~= ["-J", path];
	}

	foreach (lib; b.libs) {
		ret ~= ["-l", lib];
	}

	foreach (arg; b.xld) {
		ret ~= ["--Xld", arg];
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


public:
	this(Driver drv)
	{
		mDrv = drv;
	}

	void parse(string[] args)
	{
		ToArgs toArgs;
		mPos = 0;
		mArgs = toArgs.process(mDrv, null, args);
		filterArgs(ref mArgs, mDrv.arch, mDrv.platform);

		for (; mPos < mArgs.length; mPos++) {
			parseDefault(mArgs[mPos]);
		}
	}

	void parse(string[] args, string path, Base base)
	{
		ToArgs toArgs;
		mPos = 0;
		mArgs = toArgs.process(mDrv, path, args);
		filterArgs(ref mArgs, mDrv.arch, mDrv.platform);

		process(base);
	}


protected:
	void parseDefault(Arg arg)
	{
		if (mPos >= mArgs.length) {
			return;
		}

		switch (arg.kind) with (Arg.Kind) {
		case Exe:
			mPos++;
			exe := new Exe();
			mDrv.add(exe);
			return process(exe);
		case Lib:
			mPos++;
			lib := new Lib();
			mDrv.add(lib);
			return process(lib);
		case Directory:
			mPos++;
			base := scanDir(mDrv, arg.extra);
			return process(base);
		default: mDrv.abort("unknown argument '%s'", arg.flag);
		}
	}

	void process(Base base)
	{
		lib := cast(Lib)base;
		if (lib !is null) {
			parse(lib);
			verify(lib);
		}

		exe := cast(Exe)base;
		if (exe !is null) {
			parse(exe);
			verify(exe);
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
			case LibraryPath: lib.libPaths ~= arg.extra; break;
			case StringPath: lib.stringPaths ~= arg.extra; break;
			case ArgLD: lib.xld ~= arg.extra; break;
			case ArgCC: lib.xcc ~= arg.extra; break;
			case ArgLink: lib.xlink ~= arg.extra; break;
			case ArgLinker: lib.xlinker ~= arg.extra; break;
			case Command: handleCommand(arg.extra); break;
			default:
				return parseDefault(arg);
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
			case LibraryPath: exe.libPaths ~= arg.extra; break;
			case StringPath: exe.stringPaths ~= arg.extra; break;
			case Debug: exe.isDebug = true; break;
			case Output: exe.bin = arg.extra; break;
			case Identifier: exe.defs ~= arg.extra; break;
			case FileC: exe.srcC ~= arg.extra; break;
			case FileObj: exe.srcObj ~= arg.extra; break;
			case FileVolt: exe.srcVolt ~= arg.extra; break;
			case ArgLD: exe.xld ~= arg.extra; break;
			case ArgCC: exe.xcc ~= arg.extra; break;
			case ArgLink: exe.xlink ~= arg.extra; break;
			case ArgLinker: exe.xlinker ~= arg.extra; break;
			case Command: handleCommand(arg.extra); break;
			default:
				return parseDefault(arg);
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

	void handleCommand(string cmd)
	{
		args := parseArguments(cmd);
		if (args.length == 0) {
			return;
		}

		str := getOutput(args[0], args[1 .. $]);

		args = parseArguments(str);

		if (args.length == 0) {
			return;
		}

		ToArgs toArgs;
		res := toArgs.process(mDrv, null, args);
		filterArgs(ref res, mDrv.arch, mDrv.platform);
		mArgs = mArgs[0 .. mPos+1] ~ res ~ mArgs[mPos+1 .. $];
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
			a.extra = normalizePath(mPath ~ a.flag);
			return a;
		}

		Arg argNext(Arg.Kind kind, string error) {
			a := arg(kind);
			a.extra = getNext(error);
			return a;
		}

		Arg argNextPath(Arg.Kind kind, string error) {
			a := argNext(kind, error);
			a.extra = normalizePath(mPath ~ a.extra);
			return a;
		}

		for (mArgs.setup(args); !mArgs.empty(); mArgs.popFront()) {
			tmp := mArgs.front();

			// Deal with arguments that are compacted.
			if (tmp.length > 2 &&
			    startsWith(tmp, "-l", "-L", "-o", "-D")) {
			    	mArgs.popFront();
				mArgs.insertFront(tmp[0 .. 2], tmp[2 .. $]);
				tmp = mArgs.front();
			}

			switch (tmp) with (Arg.Kind) {
			case "--exe": arg(Exe); continue;
			case "--lib": arg(Lib); continue;
			case "--name": argNext(Name, "expected name"); continue;
			case "--dep": argNext(Dep, "expected dependency"); continue;
			case "--src-I": argNextPath(SrcDir, "expected source directory"); continue;
			case "--cmd": argNext(Command, "expected command"); continue;
			case "-l": argNext(Library, "expected library name"); continue;
			case "-L": argNext(LibraryPath, "expected library path"); continue;
			case "-J": argNextPath(StringPath, "expected string path"); continue;
			case "-d", "-debug", "--debug": arg(Debug); continue;
			case "-D": argNext(Identifier, "expected version identifier"); continue;
			case "-Xld", "--Xld": argNext(ArgLD, "expected ld arg"); continue;
			case "-Xcc", "--Xcc": argNext(ArgCC, "expected cc arg"); continue;
			case "-Xlink", "--Xlink": argNext(ArgLink, "expected link arg"); continue;
			case "-Xlinker", "--Xlinker": argNext(ArgLinker, "expected linker arg"); continue;
			case "-o", "--bin": argNextPath(Output, "expected binary file"); continue;
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

	void insertFront(string[] args...)
	{
		mArgs = args ~ mArgs;
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
