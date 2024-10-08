// Copyright 2018-2021, Collabora, Ltd.
// Copyright 2016-2018, Jakob Bornecrantz.
// SPDX-License-Identifier: BSL-1.0
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
import watt.path : fullPath, dirSeparator, mkdir, getExecDir;
import watt.process;
import watt.conv;
import watt.io.file : exists, isFile, chdir;

import battery.interfaces;
import battery.util.log : setLog, newLog, Logger;
import battery.util.file : getLinesFromFile, getTomlConfig, getStringArray, outputConfig;
import battery.util.path : cleanPath;
import battery.util.printing;
import system = battery.util.system;
import battery.policy.host;
import battery.policy.config;
import battery.policy.tools;
import battery.policy.validate;
import battery.frontend.parameters;
import battery.frontend.scanner;
import conf = battery.frontend.batteryConf;
import llvmVersion = battery.frontend.llvmVersion;
import llvmConf = battery.frontend.llvmConf;
import battery.backend.builder;
import battery.backend.command : ArgsGenerator;
import battery.testing.project;
import battery.testing.tester;
import build.util.file : modifiedMoreRecentlyThan;

import curl = battery.detect.curl;


/*!
 * So we get the right prefix on logged messages.
 */
private global log: Logger = {"driver"};

/*!
 * Controls the flow of the program.
 */
class DefaultDriver : Driver
{
public:
	enum BatteryDirectory = ".battery";
	enum BatteryConfigFile = "${BatteryDirectory}${dirSeparator}config.txt";
	enum VersionNumber = "0.1.25-dev";
	enum VersionString = "battery version ${VersionNumber}";


protected:
	mLogFile: string;
	mConfig: Configuration;
	mHostConfig: Configuration;
	mBootstrapConfig: Configuration;
	mStore: Project[string];
	mExe: Exe[];
	mLib: Lib[];
	mPwd: string;
	mLLVMConf: string;
	mConf: string;

	mBootstrapCommands: Command[string];
	mTargetCommands: Command[string];
	mHostCommands: Command[string];


public:
	this(ref args: string[])
	{
		chdirPath: string;
		if (getopt(ref args, "chdir", ref chdirPath)) {
			chdir(chdirPath);
		}

		j: i32;
		if (getopt(ref args, "j", ref j)) {
			if (j <= 0) {
				info("Ignoring zero or negative j.");
			} else {
				system.forceCoreCount(cast(u32)j);
			}
		}

		conf.parseArguments(this, ref args, out mConf);

		llvmConf.parseArguments(ref args, out mLLVMConf);
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
		case "build": build(args[2 .. $]); break;
		case "config": config(args[2 .. $]); break;
		case "test": test(args[2 .. $]); break;
		case "toolchain": toolchain(args[2 .. $]); break;
		case "version": printVersion(); break;
		case "init": projectInit(args[2 .. $]); break;
		default: printUsage(); break;
		}

		io.output.flush();
		io.error.flush();
	}

	fn config(args: string[])
	{
		// Create the battery directory before the logging file.
		mkdir(BatteryDirectory);

		// Setup logging file.
		mLogFile = new "${BatteryDirectory}${dirSeparator}config-log.txt";
		newLog(mLogFile);
		log.info("starting config");

		// Load the battery config.
		batConf: BatteryConfig;
		if (conf.loadFromFile(mConf, out batConf) ||
		    conf.loadFromDir(getExecDir(), out batConf)) {
		    	log.info("Got a BatConf!");
		}

		// Filter out --release, --arch and --platform arguments.
		originalArgs := args;
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
			     arch.archToString(), platform.platformToString());
			mConfig.kind = ConfigKind.Cross;
		}

		// Parse arguments only the config arguments.
		arg := new ArgParser(this);
		arg.parseConfig(args);

		// If we get volta via the command line, no need for bootstrap config.
		if (getCmd(false, "volta") !is null) {
			mBootstrapConfig = null;
		} else if (batConf.voltaCmd !is null) {
			mBootstrapConfig = null;
		}

		// Handle bootstrapping of volted.
		if (mBootstrapConfig !is null) {
			// Need fill in bootstrap commands seperatly.
			mBootstrapConfig.llvmConf = mLLVMConf;
			mBootstrapConfig.batConf = batConf;
			doConfig(this, mBootstrapConfig);
			fillInConfigCommands(this, mBootstrapConfig);
		}

		// Do this after the arguments has been parsed.
		mConfig.llvmConf = mLLVMConf;
		mConfig.batConf = batConf;
		doConfig(this, mConfig);
		fillInConfigCommands(this, mConfig);

		// Parse the rest of the arguments.
		arg.addExtraPkgs(batConf.pkgs);
		arg.parseProjects(mConfig);

		batteryTomls: string[];
		foreach (_lib; mLib) {
			llvmVersion.addVersionIdentifiers(mConfig.llvmVersion, _lib);
			batteryTomls ~= _lib.batteryToml;
		}
		foreach (_exe; mExe) {
			llvmVersion.addVersionIdentifiers(mConfig.llvmVersion, _exe);
			batteryTomls ~= _exe.batteryToml;
		}

		applyQuirks();
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
			validateProjectNameOrAbort(this, exe.name);
		}
		foreach (lib; mLib) {
			validateProjectNameOrAbort(this, lib.name);
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

	fn build(buildArgs: string[])
	{
		bool verbose;
		getopt(ref buildArgs, "verbose", ref verbose);
		if (buildArgs.length > 0) {
			return abort("Extra arguments given to build!\n%s", buildArgs);
		}

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
		builder.build(mConfig, mBootstrapConfig, mLib, mExe, verbose);
	}

	fn test(args: string[])
	{
		build(null);
		filter := parseTestArgs(this, args);
		tester := new Tester(this);
		tester.test(mConfig, mHostConfig, mLib, mExe, filter);
	}

	fn toolchain(args: string[])
	{
		// Log to stdout
		setLog(io.output);

		res: curl.Result[];
		env := retrieveEnvironment();
		path := env.getOrNull("PATH");

		curl.detectFromPath(path, out res);
		if (res.length <= 0) {
			return abort("Could not find curl command!");
		}

		curlRetval: u32;
		curlOutput: string;

		voltaArgs := ["-o", "votla.zip", "-L", "https://github.com/VoltLang/Volta/archive/refs/tags/v0.1.3.zip"];
		wattArgs := ["-o", "watt.zip", "-L", "https://github.com/VoltLang/Watt/archive/refs/tags/v0.1.3.zip"];

		curlOutput = getOutput(res[0].cmd, voltaArgs, ref curlRetval);
		log.info(new "Output from curl '${curlRetval}':\n${curlOutput}");
		curlOutput = getOutput(res[0].cmd, voltaArgs, ref curlRetval);
		log.info(new "Output from curl '${curlRetval}':\n${curlOutput}");
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
		case "toolchain": printToolchainUsage; break;
		case "init": printInitUsage(); break;
		default: info("unknown command '%s'", args[0]);
		}
	}

	fn projectInit(args: string[])
	{
		if (args.length == 0) {
			printLogo();
		}

		name, type, reason: string;
		getopt(ref args, "init-name", ref name);
		getopt(ref args, "init-type", ref type);

		do {
			name = prompt("What is the name of the project? ");
		} while (!validateProjectNameOrInform(this, name));

		if (type == "") {
			type = choice("Is your project an", "executable", "library");
		}

		if (exists("battery.toml")) {
			io.error.writeln("This directory already has a battery.txt. Will not overwrite.");
			return;
		}

		auto ofs = new OutputFileStream("battery.toml");
		ofs.writeln("# Generated by `battery init`. Feel free to edit.");
		ofs.writeln(new "name = \"${name}\"");
		if (type == "executable") {
			ofs.writeln(new "output = \"${name}\"");
		}
		ofs.writeln("dependencies = [\"watt\"]");
		ofs.close();

		io.writeln();
		io.writeln("battery.toml generated.");
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
usage: battery [--chdir dir, -j N] <command>

These are the available commands:
	help <command>   Prints more help about a command.
	build            Build current config.
	config [args]    Configures a build.
	test             Build current config, then run tests.
	toolchain        Manage Volt toolchain.
	version          Display battery version then exit.
	init             Generate a battery.txt file in the current directory.

Normal usecase when standing in a project directory.
	$ battery config path/to/volta path/to/watt .
	$ battery build

The --chdir flag changes the working directory of the battery process
before doing anything else.
The -j flag tells battery how many programs it can run at once. By
default this is the same as the number of processors (cores) installed
in your system.
`);
	}

	fn printHelpUsage()
	{
		info("Print a help message for a given command.");
	}

	fn printBuildUsage()
	{
		info("Invoke a build generated by the config command.");
		info("");
		info("--verbose         Print the exact commands being invoked.");
	}

	fn printTestUsage()
	{
		info("Invoke a build, then run tests.");
	}

	fn printToolchainUsage()
	{
		info("Manage Volta toolchain, command in flux!");
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
		info("Set build architecture, platform, and release or debug build modes.");
		info("Not all combinations are supported.");
		info("These flags apply to all projects, command line position is disregarded.");
		info("\t--arch arch      Selects arch (x86, x86_64).");
		info("\t--platform plat  Selects platform (osx, msvc, linux).");
		info("\t--release        Builds optimised release binaries.");
		info("\t--debug          Set debug mode.");
		info("");
		info("The three following arguments create a new project.");
		info("");
		info("\tpath             Scan path for executable or library project.");
		info("\t--exe path       Create a new executable project from path.");
		info("\t--lib path       Create a new library project from path.");
		info("");
		info("");
		info("All of the following arguments apply to the last project given.");
		info("");
		info("\t--name name      Name the current project.");
		info("\t--dep depname    Add a project as dependency.");
		info("\t--src-I dir      Set the current project's source dir.");
		info("\t--cmd command    Run the command and processes output as arguments.");
		info("\t-l lib           Add a library.");
		info("\t-L path          Add a library path.");
		info("\t--llvmconf       Add path to a llvm configuration file.");
		version (OSX) {
		info("\t-framework name  Add a framework.");
		info("\t-F path          Add a framework search path.");
		}
		info("\t-J path          Define a path for string import to look for files.");
		info("\t-D ident         Define a new version flag.");
		info("\t-o outputname    Set output to outputname.");
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
	 * Quirking and verifying the config.
	 *
	 */

	fn applyQuirks()
	{
		if (mConfig.arch == Arch.AArch64 && mConfig.isCross) {
			cc := mConfig.getTool("ccompiler");
			cc.args ~= ["-isystem", "/usr/aarch64-linux-gnu/include"];
		}

		if (mConfig.arch == Arch.ARMHF && mConfig.isCross) {
			cc := mConfig.getTool("ccompiler");
			cc.args ~= ["-isystem", "/usr/arm-linux-gnueabihf/include"];
		}
	}

	fn verifyConfig()
	{
		isCross := mHostConfig !is null;
		hasRtDir: bool;
		hasRdmdTool := mBootstrapConfig !is null && mBootstrapConfig.getTool(RdmdName) !is null;
		hasGdcTool := mBootstrapConfig !is null && mBootstrapConfig.getTool(GdcName) !is null;
		hasLdcTool := mBootstrapConfig !is null && mBootstrapConfig.getTool(LdcName) !is null;
		hasVoltaDir := mStore.get("volta", null) !is null;
		hasVoltaTool := mConfig.getTool(VoltaName) !is null;

		foreach (k, v; mStore) {
			lib := cast(Lib)v;
			if (lib !is null && lib.isTheRT) {
				hasRtDir = true;
			}
		}

		if (!hasVoltaDir && !hasVoltaTool) {
			abort("Must specify a Volta directory or --cmd-volta (for now).");
		}
		if (!hasGdcTool && !hasRdmdTool && !hasLdcTool && !hasVoltaTool) {
			abort("No rdmd, gdc, or ldc found (needed right now for Volta).");
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

		if (mExe.length == 1 && !hasVoltaTool) {
			info("WARNING: Didn't specify any executables beyond Volta. (ignore if building Volta)");
		}
	}


	/*
	 *
	 * Driver functions.
	 *
	 */

	override fn normalisePath(path: string) string
	{
		version (Windows) path = normalisePathWindows(path);
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
	}

	override fn add(exe: Exe)
	{
		if (mStore.get(exe.name, null) !is null) {
			abort("Executable or Library with name '%s' already defined.", exe.name);
		}

		mExe ~= exe;
		mStore[exe.name] = exe;
	}

	fn clearProjects()
	{
		foreach (k; mStore.keys) {
			mStore.remove(k);
		}
		mExe = null;
		mLib = null;
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
		io.output.flush();
		io.error.write("error: ");
		io.error.vwritefln(fmt, ref _typeids, ref vl);
		io.error.flush();
		va_end(vl);
		if (mLogFile !is null) {
			io.error.writefln("\tSee log in: %s", mLogFile);
			io.error.flush();
		}
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
