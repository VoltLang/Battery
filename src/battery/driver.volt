// Copyright © 2016-2017, Jakob Bornecrantz.  All rights reserved.
// See copyright notice in src/battery/license.volt (BOOST ver. 1.0).
/*!
 * Holds the default implementation of the Driver class.
 */
module battery.driver;

import core.c.stdlib : exit;
import core.varargs : va_list, va_start, va_end;
import io = watt.io;
import toml = watt.toml;
import watt.text.path;
import watt.text.string : endsWith, replace, split;
import watt.text.ascii : isAlpha, isAlphaNum;
import watt.text.getopt;
import watt.io.streams : OutputFileStream;
import watt.path : fullPath, dirSeparator;
import watt.process;
import watt.conv;
import watt.io.file : exists, isFile;

import battery.configuration;
import battery.interfaces;
import battery.util.file : getLinesFromFile, getTomlConfig, getStringArray, outputConfig;
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
import build.util.file : modifiedMoreRecentlyThan;


class DefaultDriver : Driver
{
public:
	enum BatteryConfigFile = ".battery.config.txt";
	enum VersionNumber = "0.1.15";
	enum VersionString = "battery version ${VersionNumber}";


protected:
	mConfig: Configuration;
	mHostConfig: Configuration;
	mBootstrapConfig: Configuration;
	mStore: Project[string];
	mExe: Exe[];
	mLib: Lib[];
	mPwd: string;

	mBootstrapCommands: Command[string];
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
		case "init": projectInit(args[2 .. $]); break;
		default: printUsage(); break;
		}

		io.output.flush();
		io.error.flush();
	}

	fn config(args: string[])
	{
		originalArgs := args;
		// Filter out --release, --arch and --platform arguments.
		isRelease, isLTO: bool;
		findArchAndPlatform(this, ref args, ref arch, ref platform,
		                    ref isRelease, ref isLTO);
		mBootstrapConfig = getProjectHostConfig(this);
		mHostConfig = getProjectHostConfig(this);
		mConfig = getProjectConfig(this, arch, platform);

		mBootstrapConfig.kind = ConfigKind.Bootstrap;
		mBootstrapConfig.isRelease = true;
		mHostConfig.kind = ConfigKind.Host;
		mHostConfig.isRelease = true;

		mConfig.kind = ConfigKind.Native;
		mConfig.isRelease = isRelease;
		mConfig.isLTO = isLTO;

		// Are we not cross compiling.
		if (arch == mHostConfig.arch &&
		    platform == mHostConfig.platform) {
			mHostConfig = null;
			info("native compile");
		} else {
			info("cross compiling to %s-%s",
			     .toString(arch), .toString(platform));
			mConfig.kind = ConfigKind.Cross;
		}

		// Parse arguments only the config arguments.
		arg := new ArgParser(this);
		arg.parseConfig(args);

		// If we get volta via the command line, no need for bootstrap config.
		if (getCmd(false, "volta") !is null) {
			mBootstrapConfig = null;
		}

		// Handle bootstrapping of volted.
		if (mBootstrapConfig !is null) {
			// Need fill in bootstrap commands seperatly.
			doConfig(this, mBootstrapConfig);
			fillInConfigCommands(this, mBootstrapConfig);
		}

		// Do this after the arguments has been parsed.
		doConfig(this, mConfig);
		fillInConfigCommands(this, mConfig);

		// Parse the rest of the arguments.
		arg.parseProjects(mConfig);

		batteryTomls: string[];
		fn addProjectBatteryTxt(prj: Project)
		{
			batteryTomls ~= prj.batteryToml;
			foreach (child; prj.children) {
				/* Calculating the dependency graph
				 * here to avoid some spurious (but harmless)
				 * listings here isn't worth it.
				 */
				addProjectBatteryTxt(child);
			}
		}
		foreach (_lib; mLib) {
			addProjectBatteryTxt(_lib);
		}
		foreach (_exe; mExe) {
			addProjectBatteryTxt(_exe);
		}

		configSanity();
		verifyConfig();
		bootstrapArgs: string[][2];
		if (mBootstrapConfig !is null) {
			bootstrapArgs[0] = getArgs(true, mBootstrapConfig.env);
			bootstrapArgs[1] = getArgs(true, mBootstrapConfig.tools.values);
		}
		outputConfig(BatteryConfigFile, VersionNumber, originalArgs, batteryTomls,
			getArgs(arch, platform, mConfig.isRelease, mConfig.isLTO),
			getArgs(false, mConfig.env),
			getArgs(false, mConfig.tools.values),
			bootstrapArgs[0], bootstrapArgs[1],
			getArgs(mLib, mExe));
	}

	fn configSanity()
	{
		foreach (exe; mExe) {
			validateName(exe.name);
		}
		foreach (lib; mLib) {
			validateName(lib.name);
		}
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

	fn validateName(name: string)
	{
		if (!validName(name)) {
			abort("'%s' is not a valid name for a project.", name);
		}
	}

	fn validName(name: string) bool
	{
		if (name.length == 0 || (!isAlpha(name[0]) && name[0] != '_')) {
			return false;
		}
		foreach (c: dchar; name[1 .. $]) {
			if (!isAlphaNum(c) && c != '_') {
				return false;
			}
		}
		return true;
	}

	fn build()
	{
		root: toml.Value;
		if (!getTomlConfig(BatteryConfigFile, out root)) {
			return abort("must first run the 'config' command");
		}

		auto inputs = getStringArray(root["battery"]["config"]["input"].array());
		foreach (btxt; inputs) {
			if (exists(btxt) && isFile(btxt) &&
			btxt.modifiedMoreRecentlyThan(BatteryConfigFile)) {
				info("battery.txt newer than config file, regenerating config file...");
				cargs := getStringArray(root["battery"]["config"]["args"].array());
				config(cargs);
				if (!getTomlConfig(BatteryConfigFile, out root)) {
					return abort("failed to regenerated config");
				}
				clearProjects();
				break;
			}
		}

		args := getStringArray(root["battery"]["config"]["cache"].array());

		// Filter out --release, --arch and --platform arguments.
		isRelease, isLTO: bool;
		findArchAndPlatform(this, ref args, ref arch, ref platform,
		                    ref isRelease, ref isLTO);

		// Get the configs.
		mBootstrapConfig = getProjectHostConfig(this);
		mHostConfig = getProjectHostConfig(this);
		mConfig = getProjectConfig(this, arch, platform);

		mBootstrapConfig.kind = ConfigKind.Bootstrap;
		mBootstrapConfig.isRelease = true;
		mHostConfig.kind = ConfigKind.Host;
		mHostConfig.isRelease = true;

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

		// If we have the volta tool ignore the bootstrap config.
		if (getCmd(false, "volta") !is null) {
			mBootstrapConfig = null;
		}

		// Handle cross compiling.
		if (mBootstrapConfig !is null) {
			// Need fill in host commands.
			foreach (k, v; mBootstrapCommands) {
				mBootstrapConfig.tools[k] = v;
			}
			fillInConfigCommands(this, mBootstrapConfig);
		}

/*
		// Handle cross compiling.
		if (mHostConfig !is null) {
			// Need fill in host commands.
			foreach (k, v; mHostCommands) {
				mHostConfig.tools[k] = v;
			}
			fillInConfigCommands(this, mHostConfig);
		}
*/

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
		builder.build(mConfig, mBootstrapConfig, mLib, mExe);
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

	fn projectInit(args: string[])
	{
		if (args.length == 0) {
			printLogo();
		}

		name, type: string;
		getopt(ref args, "init-name", ref name);
		getopt(ref args, "init-type", ref type);

		while (!validName(name)) {
			if (name != "") {
				info("'%s' is not a valid name for a project.", name);
				info("Valid names start with a letter or '_', and only contain");
				info("letters, digits, and underscores.");
			}
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
		ofs.writeln("--name");
		ofs.writeln(name);
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
		info("| | < | ${VersionString}");
		info("| |-/ | \"Batteries Included\"");
		info("+--=--+");
		info("");
	}

	fn printVersion()
	{
		info("${VersionString}");
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
		info("--init-type type   Is the project an 'executable' or 'library'?");
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
		info("\t-framework name  Add a framework.");
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
		hasRtDir: bool;
		hasRdmdTool := mBootstrapConfig !is null && mBootstrapConfig.getTool(RdmdName) !is null;
		hasVoltaDir := mStore.get("volta", null) !is null;
		hasVoltaTool := mConfig.getTool(VoltaName) !is null;

		foreach (k, v; mStore) {
			lib := cast(Lib)v;
			if (lib !is null && lib.isTheRT) {
				hasRtDir = true;
			}
		}

		if (!hasRdmdTool && !hasVoltaTool) {
			abort("No rdmd found (needed right now for Volta).");
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

		if (mExe.length == 1) {
			info("WARNING: Didn't specify any executables beyond Volta. (ignore if building Volta)");
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

	override fn addEnv(boot: bool, name: string, value: string)
	{
		if (boot && mBootstrapConfig is null) {
			abort("can not use bootstrap envs when not cross compiling");
		}
		(boot ? mBootstrapConfig : mConfig).env.set(name, value);
	}

	override fn setCmd(boot: bool, name: string, c: Command)
	{
		if (boot && mBootstrapConfig is null) {
			abort("can not use bootstrap commands when not cross compiling");
		}
		if (boot) {
			mBootstrapCommands[name] = c;
		} else {
			mTargetCommands[name] = c;
		}
	}

	override fn addCmd(boot: bool, name: string, cmd: string)
	{
		c := new Command();
		c.name = name;
		c.cmd = cmd;

		setCmd(boot, name, c);
	}

	override fn addCmdArg(boot: bool, name: string, arg: string)
	{
		c := getCmd(boot, name);
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

	fn clearProjects()
	{
		foreach (k; mStore.keys) {
			mStore.remove(k);
		}
		mExe = null;
		mLib = null;
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

	override fn getCmd(boot: bool, name: string) Command
	{
		if (boot && mBootstrapConfig is null) {
			abort("can not use boot commands when not cross compiling");
		}

		c: Command*;
		if (boot) {
			c = name in mBootstrapCommands;
		} else {
			c = name in mTargetCommands;
		}
		if (c is null) {
			return null;
		}
		return *c;
	}
}
