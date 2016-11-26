// Copyright © 2016, Jakob Bornecrantz.  All rights reserved.
// See copyright notice in src/battery/license.volt (BOOST ver. 1.0).
/**
 * Holds the default implementation of the Driver class.
 */
module battery.driver;

import core.stdc.stdlib : exit;
import core.varargs : va_list, va_start, va_end;
import io = watt.io;
import watt.text.path;
import watt.text.string : endsWith, replace;
import watt.io.streams : OutputFileStream;
import watt.path : fullPath, dirSeparator;
import watt.process;

import battery.configuration;
import battery.interfaces;
import battery.util.file : getLinesFromFile;
import battery.policy.host;
import battery.policy.config;
import battery.policy.tools;
import battery.frontend.parameters;
import battery.frontend.scanner;
import battery.backend.builder;
import battery.backend.command : ArgsGenerator;


class DefaultDriver : Driver
{
public:
	enum BatteryConfigFile = ".battery.config.txt";
	enum BatteryTeslaConfig = ".battery.tesla.json";


protected:
	mConfig: Configuration;
	mHostConfig: Configuration;
	mStore: Base[string];
	mExe: Exe[];
	mLib: Lib[];
	mPwd: string;


public:
	this()
	{
		arch = HostArch;
		platform = HostPlatform;
		mPwd = new string(fullPath("."), dirSeparator);
	}

	fn process(args: string[])
	{
		switch (args.length) {
		case 1: return printUsage();
		default:
		}

		switch (args[1]) {
		case "help": return help(args[2 .. $]);
		case "build": return build(args[2 .. $]);
		case "config": return config(args[2 .. $]);
		case "test": return test(args[2 .. $]);
		case "version": return printVersion();
		default: return printUsage();
		}
	}

	fn config(args: string[])
	{
		// Filter out --arch and --platform arguments.
		findArchAndPlatform(this, ref args, ref arch, ref platform);
		mHostConfig = getBaseHostConfig(this);
		mConfig = getBaseConfig(this, arch, platform);

		// Are we not cross compiling.
		if (arch == mHostConfig.arch &&
		    platform == mHostConfig.platform) {
			mHostConfig = null;
			info("native compile");
		} else {
			info("cross compiling to %s-%s",
			     .toString(arch), .toString(platform));
		}

		// Parse arguments.
		arg := new ArgParser(this);
		arg.parse(args);

		// Handle cross compiling.
		if (mHostConfig !is null) {
			// Need fill in host commands seperatly.
			doConfig(this, mHostConfig);
			fillInConfigCommands(this, mHostConfig);
		}

		// Do this after the arguments has been parsed.
		doConfig(this, mConfig);
		fillInConfigCommands(this, mConfig);

		configSanity();

		verifyConfig();

		ofs := new OutputFileStream(BatteryConfigFile);
		foreach (r; getArgs(arch, platform)) {
			ofs.write(r);
			ofs.put('\n');
		}
		foreach (r; getArgs(false, mConfig.env)) {
			ofs.write(r);
			ofs.put('\n');
		}
		foreach (r; getArgs(false, mConfig.commands.values)) {
			ofs.write(r);
			ofs.put('\n');
		}
		if (mHostConfig !is null) {
			foreach (r; getArgs(true, mHostConfig.env)) {
				ofs.write(r);
				ofs.put('\n');
			}
			foreach (r; getArgs(true, mHostConfig.commands.values)) {
				ofs.write(r);
				ofs.put('\n');
			}
		}
		foreach (r; getArgs(mLib, mExe)) {
			ofs.write(r);
			ofs.put('\n');
		}
		ofs.flush();
		ofs.close();

		writeTestConfig();
	}

	fn configSanity()
	{
		foundTest := false;
		foreach (exe; mExe) {
			if (exe.testDir !is null) {
				foundTest = true;
				break;
			}
		}
		if (!foundTest) {
			foreach (lib; mLib) {
				if (lib.testDir !is null) {
					foundTest = true;
					break;
				}
			}
		}
		if (foundTest) {
			tesla := getTool(false, "tesla");
			if (tesla is null) {
				info("tesla needed on path (for now) to run tests");
			}
		}

		foreach (k, b; mStore) {
			foreach (dep; b.deps) {
				dp := dep in mStore;
				if (dp is null) {
					io.error.writefln("No dependency '%s' found.", dep);
					switch (dep) {
					case "watt":
						io.error.writefln("Download Watt from https://github.com/VoltLang/Watt");
						break;
					case "amp":
						io.error.writefln("Download Amp from https://github.com/VoltLang/Amp");
						break;
					default:
						break;
					}
					exit(-1);
				}
			}
		}
	}

	fn build(args: string [])
	{
		args = null;
		if (!getLinesFromFile(BatteryConfigFile, ref args)) {
			return abort("must first run the 'config' command");
		}

		// Filter out --arch and --platform arguments.
		findArchAndPlatform(this, ref args, ref arch, ref platform);

		// Get the configs.
		mHostConfig = getBaseHostConfig(this);
		mConfig = getBaseConfig(this, arch, platform);

		// Parse arguments.
		arg := new ArgParser(this);
		arg.parse(args);

		// Handle cross compiling.
		if (arch != mHostConfig.arch ||
		    platform != mHostConfig.platform) {
			// Need fill in host commands.
			fillInConfigCommands(this, mHostConfig);
		} else {
			// Just reuse the host config.
			mHostConfig = null;
		}

		// Do this after the arguments has been parsed.
		fillInConfigCommands(this, mConfig);

		// Do the actual build now.
		builder := new Builder(this);
		builder.build(mConfig, mHostConfig, mLib, mExe);
		doTest();
	}

	fn test(args: string[])
	{
		build(args);
		doTest();
	}

	fn doTest()
	{
		tesla := getTool(false, "tesla");
		if (tesla is null) {
			return;
		}

		teslaArgs := [tesla.cmd, "-f", BatteryTeslaConfig];
		foundTest := false;
		foreach (exe; mExe) {
			if (exe.testDir !is null) {
				foundTest = true;
				teslaArgs ~= ["-d", exe.testDir];
			}
		}
		foreach (lib; mLib) {
			if (lib.testDir !is null) {
				foundTest = true;
				teslaArgs ~= ["-d", lib.testDir];
			}
		}
		if (!foundTest) {
			return;
		}
		pid := spawnProcess(tesla.cmd, teslaArgs);
		pid.wait();
	}

	fn help(args: string[])
	{
		if (args.length <= 0) {
			return printUsage();
		}

		switch (args[0]) {
		case "help": printHelpUsage(); break;
		case "build": printBuildUsage(); break;
		case "config": printConfigUsage(); break;
		case "test": printTestUsage(); break;
		default: info("unknown command '%s'", args[0]);
		}
	}

	fn printVersion()
	{
		info("battery version 0.1.1");
	}

	fn printUsage()
	{
		printVersion();
		info(`
usage: battery <command>

These are the available commands:
	help <command>   Prints more help about a command.
	build            Build current config.
	config [args]    Configures a build.
	test             Build current config, then run Tesla.
	version          Display battery version then exit.

Normal usecase when standing in a project directory.
	$ battery config path/to/volta path/to/watt .
	$ battery build`);
	}

	fn printHelpUsage()
	{
		info("Print a help message for a given command.");
	}

	fn printBuildUsage()
	{
		info("Invoke a build generated by the config command.");
	}

	fn printTestUsage()
	{
		info("Invoke a build, then test with Tesla.");
	}

	fn printConfigUsage()
	{
		info("");
		info("The following two arguments controlls which target battery compiles against.");
		info("Not all combinations are supported.");
		info("\t--arch arch      Selects arch (x86, x86_64).");
		info("\t--platform plat  Selects platform (osx, msvc, linux).");
		info("");
		info("The three following arguments create a new target.");
		info("");
		info("\tpath             Scan directory for executable or library target.");
		info("\t--exe            Create a new executable target.");
		info("\t--lib            Create a new library target.");
		info("");
		info("");
		info("All of the following arguments apply to the last target given.");
		info("");
		info("\t--name name      Name the current target.");
		info("\t--dep depname    Add a target as dependency.");
		info("\t--src-I dir      Set the current targets source dir.");
		info("\t--cmd command    Run the command and processes output as arguments.");
		info("\t-l lib           Add a library.");
		info("\t-L path          Add a library path.");
		info("\t-J path          Define a path for string import to look for files.");
		info("\t-D ident         Define a new version flag.");
		info("\t-o outputname    Set output to outputname.");
		info("\t--debug          Set debug mode.");
		info("\t--Xld            Add an argument when invoking the ld linker.");
		info("\t--Xcc            Add an argument when invoking the cc linker.");
		info("\t--Xlink          Add an argument when invoking the MSVC link linker.");
		info("\t--Xlinker        Add an argument when invoking all different linkers.");
		info("");
		info("");
		info("These arguments are used to create optional arch & platform arguments.");
		info("");
		info("\t--if-'platform'  Only apply the following argument if the platform is this.");
		info("\t--if-'arch'      Only apply the following argument if the arch is this.");
		info("\t                 (The if args are cumulative so that multiple");
		info("\t                  arch & platforms or togther, like so:");
		info("\t                  ('arch' || 'arch') && 'platform')");
	}


	/*
	 *
	 * Verifying the condig.
	 *
	 */

	fn verifyConfig()
	{
		isCross := mHostConfig !is null;
		hasRtDir := mStore.get("rt", null) !is null;
		hasRdmdTool := getTool(false, "rdmd") !is null;
		hasVoltaDir := mStore.get("volta", null) !is null;
		hasVoltaTool := getTool(false, "volta") !is null;

		if (isCross && !hasVoltaTool) {
			abort("Must use --volta-cmd when cross compiling");
		}
		if (!hasVoltaDir && !hasVoltaTool) {
			abort("Must specify a Volta directory or --cmd-volta (for now).");
		}
		if (!hasRtDir) {
			abort("Must specify a Volta rt directory (for now).");
		}

		if (mConfig.linkerCmd is null) {
			abort("No system linker found.");
		}
		if (mConfig.ccCmd is null) {
			abort("No system c compiler found.");
		}
		if (!hasRdmdTool && !hasVoltaTool) {
			abort("No rdmd found (needed right now for Volta).");
		}

		if (mExe.length == 0) {
			info("warning: Didn't specify any executables, will not do anything.");
		}
	}


	/*
	 *
	 * Driver functions.
	 *
	 */

	override fn normalizePath(path: string) string
	{
		version (Windows) path = normalizePathWindows(path);
		return removeWorkingDirectoryPrefix(fullPath(path));
	}

	override fn removeWorkingDirectoryPrefix(path: string) string
	{
		if (path.length > mPwd.length &&
			path[0 .. mPwd.length] == mPwd) {
			path = path[mPwd.length .. $];
		}

		return path;
	}

	override fn addEnv(host: bool, name: string, value: string)
	{
		if (host && mHostConfig is null) {
			abort("can not use host envs when not cross compiling");
		}
		(host ? mHostConfig : mConfig).env.set(name, value);
	}

	override fn setTool(host: bool, name: string, c: Command)
	{
		if (host && mHostConfig is null) {
			abort("can not use host commands when not cross compiling");
		}
		(host ? mHostConfig : mConfig).commands[name] = c;
	}

	override fn addToolCmd(host: bool, name: string, cmd: string)
	{
		c := new Command();
		c.name = name;
		c.cmd = cmd;

		switch (name) {
		case "clang": c.print = ClangPrint; break;
		case "link": c.print = LinkPrint; break;
		case "cl": c.print = CLPrint; break;
		case "volta": c.print = VoltaPrint; break;
		case "rdmd": c.print = RdmdPrint; break;
		case "nasm": c.print = NasmPrint; break;
		case "tesla": c.print = TeslaPrint; break;
		default:
			abort("unknown tool '%s' (%s)", name, cmd);
		}

		setTool(host, name, c);
	}

	override fn addToolArg(host: bool, name: string, arg: string)
	{
		c := getTool(host, name);
		if (c is null) {
			abort("tool not defined '%s'", name);
		}
		c.args ~= arg;
	}

	override fn add(lib: Lib)
	{
		if (mStore.get(lib.name, null) !is null) {
			abort("Executable or Library with name '%s' already defined.", lib.name);
		}

		mLib ~= lib;
		mStore[lib.name] = lib;
	}

	override fn add(exe: Exe)
	{
		if (mStore.get(exe.name, null) !is null) {
			abort("Executable or Library with name '%s' already defined.", exe.name);
		}

		mExe ~= exe;
		mStore[exe.name] = exe;
	}

	override fn action(fmt: Fmt, ...)
	{
		vl: va_list;
		va_start(vl);
		io.output.write("  BATTERY  ");
		io.output.vwritefln(fmt, ref _typeids, ref vl);
		io.output.flush();
		va_end(vl);
	}

	override fn info(fmt: Fmt, ...)
	{
		vl: va_list;
		va_start(vl);
		io.output.vwritefln(fmt, ref _typeids, ref vl);
		io.output.flush();
		va_end(vl);
	}

	override fn abort(fmt: Fmt, ...)
	{
		vl: va_list;
		va_start(vl);
		io.output.write("error: ");
		io.output.vwritefln(fmt, ref _typeids, ref vl);
		io.output.flush();
		va_end(vl);
		exit(-1);
	}


	/*
	 *
	 * Helper functions.
	 *
	 */

	fn getTool(host: bool, name: string) Command
	{
		if (host && mHostConfig is null) {
			abort("can not use host commands when not cross compiling");
		}
		conf := (host ? mHostConfig : mConfig);
		c := name in conf.commands;
		if (c is null) {
			return null;
		}
		return *c;
	}

	fn getTestProject() Base
	{
		if (mExe.length != 2) {
			return null;
		}
		testProject: Base;
		foreach (exe; mExe) {
			if (exe.name != "volta") {
				return exe;
			}
		}
		return null;
	}

	fn writeTestConfig()
	{
		testProject := getTestProject();
		if (testProject is null) {
			return;
		}

		fn slashEscape(str: string) string
		{
			version (!Windows) {
				return str;
			} else {
				return str.replace("\\", "\\\\");
			}
		}

		gen: ArgsGenerator;
		gen.setup(mHostConfig is null ? mConfig : mHostConfig, mLib, mExe);
		voltpath := slashEscape(gen.buildDir ~ dirSeparator ~ "volted");
		rtpath := slashEscape(gen.buildDir ~ dirSeparator ~ "rt.o");
		wattpath := slashEscape(gen.buildDir ~ dirSeparator ~ "watt.o");
		version (Windows) {
			if (!endsWith(voltpath, ".exe")) {
				voltpath ~= ".exe";
			}
		}

		ofs := new OutputFileStream(BatteryTeslaConfig);
		ofs.write("{\n  \"cmds\": {\n    \"volta\": {\"path\": \"");
		ofs.write(voltpath);
		ofs.write("\", \"args\":[");
		foreach (i, arg; gen.genVoltaArgs(testProject)) {
			ofs.writef("\"%s\", ", slashEscape(arg));
		}
		ofs.writef("\"%s\", \"%s\"]}", rtpath, wattpath);
		exe := cast(Exe)testProject;
		if (exe !is null) {
			exepath := slashEscape("." ~ dirSeparator ~ exe.bin);
			version (Windows) {
				if (!endsWith(exepath, ".exe")) {
					exepath ~= ".exe";
				}
			}
			ofs.writefln(",\n    \"%s\": {\"path\": \"%s\", \"args\":[]}", exe.name, exepath);
		}
		ofs.writefln("  }\n}");
		ofs.flush();
		ofs.close();
	}
}
