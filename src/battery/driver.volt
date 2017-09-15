// Copyright © 2016-2017, Jakob Bornecrantz.  All rights reserved.
// See copyright notice in src/battery/license.volt (BOOST ver. 1.0).
/*!
 * Holds the default implementation of the Driver class.
 */
module battery.driver;

import core.c.stdlib : exit;
import core.varargs : va_list, va_start, va_end;
import io = watt.io;
import watt.text.path;
import watt.text.string : endsWith, replace, split;
import watt.text.getopt;
import watt.io.streams : OutputFileStream;
import watt.path : fullPath, dirSeparator;
import watt.process;
import watt.conv;
import watt.io.file : exists;

import battery.configuration;
import battery.interfaces;
import battery.util.file : getLinesFromFile;
import battery.util.path : cleanPath;
import battery.policy.host;
import battery.policy.config;
import battery.policy.tools;
import battery.frontend.parameters;
import battery.frontend.scanner;
import battery.backend.builder;
import battery.backend.command : ArgsGenerator;
import battery.testing.project;
import battery.testing.tester;


class DefaultDriver : Driver
{
public:
	enum BatteryConfigFile = ".battery.config.txt";


protected:
	mConfig: Configuration;
	mHostConfig: Configuration;
	mStore: Project[string];
	mExe: Exe[];
	mLib: Lib[];
	mPwd: string;

	mTargetCommands: Command[string];
	mHostCommands: Command[string];


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
		case "help": help(args[2 .. $]); break;
		case "build": build(); break;
		case "config": config(args[2 .. $]); break;
		case "test": test(args[2 .. $]); break;
		case "version": printVersion(); break;
		case "init": init(args[2 .. $]); break;
		default: printUsage(); break;
		}

		io.output.flush();
		io.error.flush();
	}

	fn config(args: string[])
	{
		// Filter out --release, --arch and --platform arguments.
		isRelease, isLTO: bool;
		findArchAndPlatform(this, ref args, ref arch, ref platform,
		                    ref isRelease, ref isLTO);
		mHostConfig = getProjectHostConfig(this);
		mConfig = getProjectConfig(this, arch, platform);

		// Are we not cross compiling.
		if (arch == mHostConfig.arch &&
		    platform == mHostConfig.platform) {
			mHostConfig = null;
			mConfig.kind = ConfigKind.Native;
			mConfig.isRelease = isRelease;
			mConfig.isLTO = isLTO;
			info("native compile");
		} else {
			info("cross compiling to %s-%s",
			     .toString(arch), .toString(platform));
			mHostConfig.kind = ConfigKind.Host;
			mHostConfig.isRelease = true;
			mConfig.kind = ConfigKind.Cross;
			mConfig.isRelease = isRelease;
			mConfig.isLTO = isLTO;
		}

		// Parse arguments only the config arguments.
		arg := new ArgParser(this);
		arg.parseConfig(args);

		// If we get volta via the command line, no need for host config.
		if (getCmd(false, "volta") !is null) {
			mHostConfig = null;
		}

		// Handle cross compiling.
		if (mHostConfig !is null) {
			// Need fill in host commands seperatly.
			doConfig(this, mHostConfig);
			fillInConfigCommands(this, mHostConfig);
		}

		// Do this after the arguments has been parsed.
		doConfig(this, mConfig);
		fillInConfigCommands(this, mConfig);

		// Parse the rest of the arguments.
		arg.parseProjects(mConfig);

		configSanity();

		verifyConfig();

		ofs := new OutputFileStream(BatteryConfigFile);
		foreach (r; getArgs(arch, platform, mConfig.isRelease, mConfig.isLTO)) {
			ofs.write(r);
			ofs.put('\n');
		}
		foreach (r; getArgs(false, mConfig.env)) {
			ofs.write(r);
			ofs.put('\n');
		}

		foreach (r; getArgs(false, mConfig.tools.values)) {
			ofs.write(r);
			ofs.put('\n');
		}
		if (mHostConfig !is null) {
			foreach (r; getArgs(true, mHostConfig.env)) {
				ofs.write(r);
				ofs.put('\n');
			}
			foreach (r; getArgs(true, mHostConfig.tools.values)) {
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
	}

	fn configSanity()
	{
		foreach (k, b; mStore) {
			foreach (dep; b.deps) {
				dp := dep in mStore;
				if (dp !is null) {
					continue;
				}
				switch (dep) {
				case "watt":
					abort("Library Watt not found.\nDownload Watt from https://github.com/VoltLang/Watt");
					break;
				case "amp":
					abort("Library Amp not found.\nDownload Amp from https://github.com/VoltLang/Amp");
					break;
				default:
					abort("No dependency '%s' found.", dep);
					break;
				}
			}
		}
	}

	fn build()
	{
		args: string[];
		if (!getLinesFromFile(BatteryConfigFile, ref args)) {
			return abort("must first run the 'config' command");
		}

		// Filter out --release, --arch and --platform arguments.
		isRelease, isLTO: bool;
		findArchAndPlatform(this, ref args, ref arch, ref platform,
		                    ref isRelease, ref isLTO);

		// Get the configs.
		mHostConfig = getProjectHostConfig(this);
		mConfig = getProjectConfig(this, arch, platform);

		// Parse arguments only the config arguments.
		arg := new ArgParser(this);
		arg.parseConfig(args);

		// Are we native or not?
		if (arch == mHostConfig.arch &&
		    platform == mHostConfig.platform) {
			mConfig.kind = ConfigKind.Native;
			mHostConfig = null;
		} else {
			mConfig.kind = ConfigKind.Cross;
		}

		// If we have the volta tool ignore the host config.
		if (getCmd(false, "volta") !is null) {
			mHostConfig = null;
		}

		// Handle cross compiling.
		if (mHostConfig !is null) {
			// Need fill in host commands.
			foreach (k, v; mHostCommands) {
				mHostConfig.tools[k] = v;
			}
			mHostConfig.kind = ConfigKind.Host;
			mHostConfig.isRelease = true;
			fillInConfigCommands(this, mHostConfig);
		}

		// Do this after the arguments has been parsed.
		foreach (k, v; mTargetCommands) {
			mConfig.tools[k] = v;
		}
		mConfig.isRelease = isRelease;
		mConfig.isLTO = isLTO;
		fillInConfigCommands(this, mConfig);

		// Parse the rest of the arguments.
		arg.parseProjects(mConfig);

		// Do the actual build now.
		builder := new Builder(this);
		builder.build(mConfig, mHostConfig, mLib, mExe);
	}

	fn test(args: string[])
	{
		build();
		filter := parseTestArgs(this, args);
		tester := new Tester(this);
		tester.test(mConfig, mHostConfig, mLib, mExe, filter);
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
		case "init": printInitUsage(); break;
		default: info("unknown command '%s'", args[0]);
		}
	}

	fn init(args: string[])
	{
		if (args.length == 0) {
			printLogo();
		}

		name, type: string;
		getopt(ref args, "init-name", ref name);
		getopt(ref args, "init-type", ref type);

		while (name == "") {
			name = prompt("What is the name of the project? ");
		}
		if (type == "") {
			type = choice("Is your project an", "executable", "library");
		}

		if (exists("battery.txt")) {
			io.error.writeln("This directory already has a battery.txt. Will not overwrite.");
			return;
		}

		auto ofs = new OutputFileStream("battery.txt");
		ofs.writeln("# Generated by `battery init`. Feel free to edit.");
		if (type == "executable") {
			ofs.writeln("-o");
			ofs.writeln(name);
		}
		ofs.writeln("--dep");
		ofs.writeln("watt");
		ofs.close();

		io.writeln();
		io.writeln("battery.txt generated.");
		io.writeln("Run 'battery config' and then 'battery build' to build your project.");
	}

	fn prompt(question: string) string
	{
		io.write(question);
		io.write(" ");
		io.output.flush();
		return io.readln();
	}

	fn choice(question: string, options: string[]...) string
	{
		io.writeln("Enter the choice, or the appropriate number.");
		while (true) {
			io.write(question);
			foreach (i, option; options) {
				io.writef(" (%s) %s", i+1, option);
				if (i < options.length - 1) {
					io.writef(", or a");
				}
			}
			io.write("? ");
			io.output.flush();
			response := io.readln();
			foreach (i, option; options) {
				if (toLower(option) == toLower(response)) {
					return option;
				}
				if (.toString(i + 1) == response) {
					return option;
				}
			}
			io.writefln("Please enter a number between %s and %s, or the option desired.", 1, options.length);
			io.output.flush();
		}
	}

	fn printLogo()
	{
		info("   _   ");
		info("+-+-+-+");
		info(`| |-\ |`);
		info("| | < | ${VERSION_STRING}");
		info("| |-/ | \"Batteries Included\"");
		info("+--=--+");
		info("");
	}

	enum VERSION_STRING = "battery version 0.1.13";
	fn printVersion()
	{
		info("${VERSION_STRING}");
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
	init             Generate a battery.txt file in the current directory.

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

	fn printInitUsage()
	{
		info("Generate a battery.txt file. Run with no arguments to be prompted,");
		info("or use the following arguments to script:");
		info("");
		info("--init-name name   The name of the project.");
		info("--init-type type   Is the project an 'executable' or a 'library'?");
	}

	fn printConfigUsage()
	{
		info("");
		info("The following two arguments controlls which target battery compiles against.");
		info("Not all combinations are supported.");
		info("\t--arch arch      Selects arch (x86, x86_64).");
		info("\t--platform plat  Selects platform (osx, msvc, linux).");
		info("\t--release        Builds optimized release binaries.");
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
		version (OSX) {
		info("\t--framework name Add a framework.");
		info("\t-F path          Add a framework search path.");
		}
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
		hasRdmdTool := mConfig.getTool(RdmdName) !is null;
		hasVoltaDir := mStore.get("volta", null) !is null;
		hasVoltaTool := mConfig.getTool(VoltaName) !is null;

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
			info("warning: Didn't specify any executables.");
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

	override fn setCmd(host: bool, name: string, c: Command)
	{
		if (host && mHostConfig is null) {
			abort("can not use host commands when not cross compiling");
		}
		if (host) {
			mHostCommands[name] = c;
		} else {
			mTargetCommands[name] = c;
		}
	}

	override fn addCmd(host: bool, name: string, cmd: string)
	{
		c := new Command();
		c.name = name;
		c.cmd = cmd;

		setCmd(host, name, c);
	}

	override fn addCmdArg(host: bool, name: string, arg: string)
	{
		c := getCmd(host, name);
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
		addChildren(lib);
	}

	override fn add(exe: Exe)
	{
		if (mStore.get(exe.name, null) !is null) {
			abort("Executable or Library with name '%s' already defined.", exe.name);
		}

		mExe ~= exe;
		mStore[exe.name] = exe;
		addChildren(exe);
	}

	fn addChildren(b: Project)
	{
		foreach (child; b.children) {
			mStore[child.name] = child;
			addChildren(child);
		}
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

	override fn getCmd(host: bool, name: string) Command
	{
		if (host && mHostConfig is null) {
			abort("can not use host commands when not cross compiling");
		}

		c: Command*;
		if (host) {
			c = name in mHostCommands;
		} else {
			c = name in mTargetCommands;
		}
		if (c is null) {
			return null;
		}
		return *c;
	}
}
