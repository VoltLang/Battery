// Copyright © 2016, Jakob Bornecrantz.  All rights reserved.
// See copyright notice in src/battery/license.volt (BOOST ver. 1.0).
/**
 * Holds code for parsing command line options into Lib and Exe.
 */
module battery.frontend.parameters;

import watt.process;
import watt.conv : toLower;
import watt.text.path : normalizePath;
import watt.text.string : startsWith, endsWith;

import battery.configuration;
import battery.interfaces;
import battery.policy.arg;
import battery.frontend.scanner;


fn getArgs(arch: Arch, platform: Platform, isRelease: bool) string[]
{
	ret: string[] = [
		"--arch", toString(arch),
		"--platform", toString(platform)
		];
	if (isRelease) {
		ret ~= "--release";
	}
	return ret;
}

fn getArgs(host: bool, env: Environment) string[]
{
	ret: string[] = ["#", "# Environment"];
	foreach (k, v; env.store) {
		ret ~= (host ? "--host-env-" : "--env-") ~ k;
		ret ~= v;
	}
	return ret;
}

fn getArgs(host: bool, cmds: Command[]) string[]
{
	ret: string[];

	foreach (cmd; cmds) {
		name := cmd.name;
		cmdFlag := (host ? "--host-cmd-" : "--cmd-") ~ name;
		argFlag := (host ? "--host-arg-" : "--arg-") ~ name;

		ret ~= ["#", "# tool: " ~ name, cmdFlag, cmd.cmd];
		foreach (arg; cmd.args) {
			ret ~= [argFlag, arg];
		}
	}

	return ret;
}

/**
 * Turn Libs and Exes into command line arguments.
 */
fn getArgs(libs: Lib[], exes: Exe[]) string[]
{
	ret: string[];

	foreach (lib; libs) {
		ret ~= getArgsLib(lib);
	}

	foreach (exe; exes) {
		ret ~= getArgsExe(exe);
	}

	return ret;
}

fn getArgsBase(b: Base, tag: string) string[]
{
	ret := ["#",
		new string("# ", tag, ": ", b.name),
		new string("--", tag),
		b.name
	];

	foreach (dir; b.testDirs) {
		ret ~= ["--test-dir", dir];
	}

	foreach (dep; b.deps) {
		ret ~= ["--dep", dep];
	}

	foreach (def; b.defs) {
		ret ~= ["-D", def];
	}

	foreach (path; b.libPaths) {
		ret ~= ["-L", path];
	}

	foreach (framework; b.frameworks) {
		ret ~= ["--framework", framework];
	}

	foreach (path; b.frameworkPaths) {
		ret ~= ["-F", path];
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

	ret ~= b.srcAsm;

	return ret;
}

fn getArgsLib(l: Lib) string[]
{
	return getArgsBase(l, "lib");
}

fn getArgsExe(e: Exe) string[]
{
	ret := getArgsBase(e, "exe");

	if (e.isInternalD) {
		ret ~= "--internal-d";
	}

	ret ~= e.srcC;
	ret ~= e.srcD;
	ret ~= e.srcObj;
	ret ~= e.srcVolt;

	if (e.bin !is null) {
		ret ~= ["-o", e.bin];
	}

	return ret;
}

/**
 * Parser args and turns them into Libs and Exes.
 */
class ArgParser
{
public:
	mDrv: Driver;
	mArgs: Arg[];
	mPos: size_t;


public:
	this(drv: Driver)
	{
		mDrv = drv;
	}

	fn parseConfig(args: string[])
	{
		toArgs: ToArgs;
		mPos = 0;
		mArgs = toArgs.process(mDrv, null, args);
		filterArgs(ref mArgs, mDrv.arch, mDrv.platform);

		for (; mPos < mArgs.length; mPos++) {
			arg := mArgs[mPos];
			switch (arg.kind) with (Arg.Kind) {
			case Exe:
			case Lib:
			case Directory:
				return;
			case Env:
				assert(arg.flag.length > 6);
				mDrv.addEnv(false, arg.flag[6 .. $], arg.extra);
				break;
			case HostEnv:
				assert(arg.flag.length > 11);
				mDrv.addEnv(true, arg.flag[11 .. $], arg.extra);
				break;
			case ToolCmd:
				assert(arg.flag.length > 6);
				mDrv.addCmd(false, arg.flag[6 .. $], arg.extra);
				break;
			case ToolArg:
				assert(arg.flag.length > 6);
				mDrv.addCmdArg(false, arg.flag[6 .. $], arg.extra);
				break;
			case HostToolCmd:
				assert(arg.flag.length > 11);
				mDrv.addCmd(true, arg.flag[11 .. $], arg.extra);
				break;
			case HostToolArg:
				assert(arg.flag.length > 11);
				mDrv.addCmdArg(true, arg.flag[11 .. $], arg.extra);
				break;
			default: mDrv.abort("unknown argument '%s'", arg.flag);
			}
		}

	}

	fn parseProjects(c: Configuration)
	{
		for (; mPos < mArgs.length; mPos++) {
			parseDefault(c);
		}
	}

	fn parseProjects(c: Configuration, args: string[], path: string, base: Base)
	{
		toArgs: ToArgs;
		mPos = 0;
		mArgs = toArgs.process(mDrv, path, args);
		filterArgs(ref mArgs, mDrv.arch, mDrv.platform);

		process(c, base);
	}


protected:
	fn parseDefault(c: Configuration)
	{
		for (; mPos < mArgs.length; mPos++) {
			arg := mArgs[mPos];
			switch (arg.kind) with (Arg.Kind) {
			case Exe:
				mPos++;
				exe := new Exe();
				exe.name = arg.extra;
				process(c, exe);
				mDrv.add(exe);
				return;
			case Lib:
				mPos++;
				lib := new Lib();
				lib.name = arg.extra;
				process(c, lib);
				mDrv.add(lib);
				return;
			case Directory:
				mPos++;
				base := scanDir(mDrv, c, arg.extra);
				process(c, base);
				if (auto lib = cast(Lib)base) {
					mDrv.add(lib);
				} else if (auto exe = cast(Exe)base) {
					mDrv.add(exe);
				}
				return;
			case Env:
			case HostEnv:
			case ToolCmd:
			case ToolArg:
			case HostToolCmd:
			case HostToolArg:
				mDrv.abort("argument '%s' can't be used after projects", arg.flag);
				break;
			default: mDrv.abort("unknown argument '%s'", arg.flag);
			}
		}
	}

	fn process(c: Configuration, base: Base)
	{
		lib := cast(Lib)base;
		if (lib !is null) {
			parseLib(c, lib);
			verify(lib);
		}

		exe := cast(Exe)base;
		if (exe !is null) {
			parseExe(c, exe);
			verify(exe);
		}
	}

	fn parseLib(c: Configuration, lib: Lib)
	{
		for (; mPos < mArgs.length; mPos++) {
			arg := mArgs[mPos];
			switch (arg.kind) with (Arg.Kind) {
			case Name: lib.name = arg.extra; break;
			case SrcDir: lib.srcDir = arg.extra; break;
			case TestDir: lib.testDirs ~= arg.extra; break;
			case Dep: lib.deps ~= arg.extra; break;
			case Library: lib.libs ~= arg.extra; break;
			case LibraryPath: lib.libPaths ~= arg.extra; break;
			case Framework: lib.frameworks ~= arg.extra; break;
			case FrameworkPath: lib.frameworkPaths ~= arg.extra; break;
			case StringPath: lib.stringPaths ~= arg.extra; break;
			case ArgLD: lib.xld ~= arg.extra; break;
			case ArgCC: lib.xcc ~= arg.extra; break;
			case ArgLink: lib.xlink ~= arg.extra; break;
			case ArgLinker: lib.xlinker ~= arg.extra; break;
			case FileAsm: lib.srcAsm ~= arg.extra; break;
			case Command: handleCommand(c, arg.extra); break;
			default:
				return parseDefault(c);
			}
		}
	}

	fn parseExe(c: Configuration, exe: Exe)
	{
		for (; mPos < mArgs.length; mPos++) {
			arg := mArgs[mPos];
			switch (arg.kind) with (Arg.Kind) {
			case Name: exe.name = arg.extra; break;
			case SrcDir: exe.srcDir = arg.extra; break;
			case TestDir: exe.testDirs ~= arg.extra; break;
			case Dep: exe.deps ~= arg.extra; break;
			case Library: exe.libs ~= arg.extra; break;
			case LibraryPath: exe.libPaths ~= arg.extra; break;
			case Framework: exe.frameworks ~= arg.extra; break;
			case FrameworkPath: exe.frameworkPaths ~= arg.extra; break;
			case StringPath: exe.stringPaths ~= arg.extra; break;
			case InternalD: exe.isInternalD = true; break;
			case Output: exe.bin = arg.extra; break;
			case Identifier: exe.defs ~= arg.extra; break;
			case FileC: exe.srcC ~= arg.extra; break;
			case FileD: exe.srcD ~= arg.extra; break;
			case FileAsm: exe.srcAsm ~= arg.extra; break;
			case FileObj: exe.srcObj ~= arg.extra; break;
			case FileVolt: exe.srcVolt ~= arg.extra; break;
			case ArgLD: exe.xld ~= arg.extra; break;
			case ArgCC: exe.xcc ~= arg.extra; break;
			case ArgLink: exe.xlink ~= arg.extra; break;
			case ArgLinker: exe.xlinker ~= arg.extra; break;
			case Command: handleCommand(c, arg.extra); break;
			default:
				return parseDefault(c);
			}
		}
	}

	fn verify(lib: Lib)
	{
		if (lib.name is null) {
			mDrv.abort("library not given a name '--name'");
		}

		if (lib.srcDir is null) {
			mDrv.abort("library not given a source directory '--src-I'");
		}
	}

	fn verify(exe: Exe)
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

	fn handleCommand(c: Configuration, cmd: string)
	{
		args := parseArguments(cmd);
		if (args.length == 0) {
			return;
		}

		cmd = args[0];
		args = args[1 .. $];

		// See if there is a cmd added with this name.
		// Helps llvm-config to match what for the entire build.
		if (tool := c.getTool(cmd)) {
			cmd = tool.cmd;
			args = tool.args ~ args;
		}

		// Run the command and read the output.
		str := getOutput(cmd, args);

		args = parseArguments(str);

		if (args.length == 0) {
			return;
		}

		toArgs: ToArgs;
		res := toArgs.process(mDrv, null, args);
		filterArgs(ref res, mDrv.arch, mDrv.platform);
		mArgs = mArgs[0 .. mPos+1] ~ res ~ mArgs[mPos+1 .. $];
	}
}

fn parseArch(driver: Driver, a: string) Arch
{
	switch (toLower(a)) {
	case "x86":
		return Arch.X86;
	case "x86_64":
		return Arch.X86_64;
	default:
		driver.abort("unknown arch '%s'", a);
		assert(false);
	}
}

fn parsePlatform(driver: Driver, p: string) Platform
{
	switch (toLower(p)) {
	case "msvc":
		return Platform.MSVC;
	case "linux":
		return Platform.Linux;
	case "osx":
		return Platform.OSX;
	default:
		driver.abort("unknown platform '%s'", p);
		assert(false);
	}
}

fn findArchAndPlatform(driver: Driver, ref args: string[],
                       ref arch: Arch, ref platform: Platform,
                       ref isRelease: bool)
{
	isArch, isPlatform: bool;
	pos: size_t;

	foreach (arg; args) {
		if (isArch) {
			pos++;
			arch = parseArch(driver, arg);
			isArch = false;
			continue;
		}
		if (isPlatform) {
			pos++;
			platform = parsePlatform(driver, arg);
			isPlatform = false;
			continue;
		}
		switch (arg) {
		case "--arch":
			pos++;
			isArch = true;
			continue;
		case "--platform":
			pos++;
			isPlatform = true;
			continue;
		case "--debug":
			pos++;
			isRelease = false;
			continue;
		case "--release":
			pos++;
			isRelease = true;
			continue;
		default:
		}
		break;
	}
	if (isArch) {
		driver.abort("expected arch");
	}
	if (isPlatform) {
		driver.abort("expected platform");
	}
	if (pos >= args.length) {
		driver.abort("expected more arguments");
	}

	// Update length
	args = args[pos .. $];
}

struct ToArgs
{
	fn process(mDrv: Driver, mPath: string, args: string[]) Arg[]
	{
		ret: Arg[];
		mArgs: Range;
		mArgs.setup(args);


		condArch, condPlatform : int;

		fn setCondP(platform: Platform) {
			condPlatform |= 1 << platform;
		}

		fn setCondA(arch: Arch) {
			condArch |= 1 << arch;
		}

		fn getNext(error: string) string
		{
			mArgs.popFront();
			if (!mArgs.empty()) {
				return mArgs.front();
			}

			mDrv.abort(error);
			assert(false);
		}

		fn apply(arg: Arg) {
			arg.condArch = condArch;
			arg.condPlatform = condPlatform;
			condArch = condPlatform = 0;
		}

		fn arg(kind: Arg.Kind) Arg {
			a : Arg;
			ret ~= a = new Arg(kind, mArgs.front());
			apply(a);
			return a;
		}

		fn argPath(kind: Arg.Kind) Arg {
			a := arg(kind);
			path := new string(mPath, a.flag);
			a.extra = normalizePath(path);
			return a;
		}

		fn argNext(kind: Arg.Kind, error: string) Arg {
			a := arg(kind);
			a.extra = getNext(error);
			return a;
		}

		fn argNextPath(kind: Arg.Kind, error: string) Arg {
			a := argNext(kind, error);
			path := new string(mPath, a.extra);
			a.extra = normalizePath(path);
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

			// Deal with --cmd-volta and --arg-volta.
			if (tmp.length > 6 &&
			    startsWith(tmp, "--cmd-", "--arg-")) {
				isCmd := tmp[0 .. 6] == "--cmd-";
				if (isCmd) {
					argNextPath(Arg.Kind.ToolCmd, "expected command");
				} else {
					argNext(Arg.Kind.ToolArg, "expected argument");
				}
				continue;
			}

			// Deal with --env-PATH
			if (tmp.length > 6 && tmp[0 .. 6] == "--env-") {
				argNext(Arg.Kind.Env, "expected env var");
				continue;
			}

			// Deal with --host-env-PATH
			if (tmp.length > 11 && tmp[0 .. 11] == "--host-env-") {
				argNext(Arg.Kind.HostEnv, "expected env var");
				continue;
			}

			// Deal with --host-cmd-volta and --host-arg-volta.
			if (tmp.length > 11 &&
			    startsWith(tmp, "--host-cmd-", "--host-arg-")) {
				isCmd := tmp[0 .. 11] == "--host-cmd-";
				if (isCmd) {
					argNextPath(Arg.Kind.HostToolCmd, "expected command");
				} else {
					argNext(Arg.Kind.HostToolArg, "expected argument");
				}
				continue;
			}

			switch (tmp) with (Arg.Kind) {
			case "--arch": mDrv.abort("--arch argument must be first argument after config"); continue;
			case "--platform": mDrv.abort("--platform argument must be first argument after config"); continue;
			case "--debug": mDrv.abort("--debug argument must be first argument after config"); continue;
			case "--release": mDrv.abort("--release argument must be first argument after config"); continue;
			case "--exe": argNext(Exe, "expected name"); continue;
			case "--lib": argNext(Lib, "expected name"); continue;
			case "--name": argNext(Name, "expected name"); continue;
			case "--dep": argNext(Dep, "expected dependency"); continue;
			case "--test-dir": argNextPath(TestDir, "expected test directory"); continue;
			case "--src-I": argNextPath(SrcDir, "expected source directory"); continue;
			case "--cmd": argNext(Command, "expected command"); continue;
			case "-l": argNext(Library, "expected library name"); continue;
			case "-L": argNext(LibraryPath, "expected library path"); continue;
			case "--framework": argNext(Framework, "expected framework name"); continue;
			case "-F": argNext(FrameworkPath, "expected framework path"); continue;
			case "-J": argNextPath(StringPath, "expected string path"); continue;
			case "--internal-d": arg(InternalD); continue;
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
			} else if (endsWith(tmp, ".d")) {
				argPath(Arg.Kind.FileD);
			} else if (endsWith(tmp, ".volt")) {
				argPath(Arg.Kind.FileVolt);
			} else if (endsWith(tmp, ".asm")) {
				argPath(Arg.Kind.FileAsm);
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
	mArgs: string[];


public:
	fn setup(args: string[])
	{
		mArgs = args;
	}

	fn insertFront(args: string[]...)
	{
		mArgs = args ~ mArgs;
	}


public:
	/*
	 *
	 * Range
	 *
	 */

	fn front() string
	{
		if (mArgs.length > 0) {
			return mArgs[0];
		} else {
			return null;
		}
	}

	fn popFront()
	{
		if (mArgs.length > 1) {
			mArgs = mArgs[1 .. $];
		} else {
			mArgs = null;
		}
	}

	fn empty() bool
	{
		return mArgs.length == 0;
	}
}
