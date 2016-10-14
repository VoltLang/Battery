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
import watt.io.streams : OutputFileStream;
import watt.path : fullPath, dirSeparator;

import battery.configuration;
import battery.interfaces;
import battery.util.file : getLinesFromFile;
import battery.policy.host;
import battery.policy.programs;
import battery.frontend.cmd;
import battery.frontend.dir;
import battery.backend.build;


class DefaultDriver : Driver
{
public:
	enum BatteryConfigFile = ".battery.config.txt";


protected:
	mHostConfig: Configuration;
	mStore: Base[string];
	mExe: Exe[];
	mLib: Lib[];
	mPwd: string;
	mCommands: Command[string];


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
		default: return printUsage();
		}
	}

	fn config(args: string[])
	{
		// Get host config
		mHostConfig = getHostConfig(this);

		arg := new ArgParser(this);
		arg.parse(args);

		verifyConfig();

		ofs := new OutputFileStream(BatteryConfigFile);
		foreach (r; getArgs(mCommands.values)) {
			ofs.write(r);
			ofs.put('\n');
		}
		foreach (r; getArgs(mLib, mExe)) {
			ofs.write(r);
			ofs.put('\n');
		}
		ofs.flush();
		ofs.close();
	}

	fn build(args: string [])
	{
		args = null;
		if (!getLinesFromFile(BatteryConfigFile, ref args)) {
			return abort("must first run the 'config' command");
		}

		arg := new ArgParser(this);
		arg.parse(args);

		mHostConfig = getHostConfig(this);
		builder := new Builder(this);
		builder.build(mHostConfig, mLib, mExe);
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
		default: info("unknown command '%s'", args[0]);
		}
	}

	fn printUsage()
	{
		info(`
usage: battery <command>

These are the available commands:
	help <command>   Prints more help about a command.
	build            Build current config.
	config [args]    Configures a build.

Normal usecase when standing in a project directory.
	$ battery config path/to/volta path/to/watt .
	$ battery build`);
	}

	fn printHelpUsage()
	{
		info("This is where the help for 'help' goes.");
	}

	fn printBuildUsage()
	{
		info("This is where the help for 'build' goes.");
	}

	fn printConfigUsage()
	{
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
		info("\t--Xld            Add an argument when inoking the ld linker.");
		info("\t--Xcc            Add an argument when inoking the cc linker.");
		info("\t--Xlink          Add an argument when inoking the MSVC link linker.");
		info("\t--Xlinker        Add an argument when inoking all different linkers.");
		info("");
		info("");
		info("These arguments are used to create optional arch & platform arguments.");
		info("");
		info("\t--if-'platform'  Only apply the following argument if platform is this.");
		info("\t--if-'arch'      Only apply the following argument if arch is this.");
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
		rt := mStore.get("rt", null);
		volta := mStore.get("volta", null);
		if (volta is null) {
			abort("Must specify a Volta directory (for now).");
		}
		if (rt is null) {
			abort("Must specify a Volta directory (for now).");
		}

		if (mHostConfig.linkerCmd is null) {
			abort("No system linker found.");
		}
		if (mHostConfig.ccCmd is null) {
			abort("No system c compiler found.");
		}
		if (mHostConfig.rdmdCmd is null) {
			abort("No rdmd found (needed right now for Volta).");
		}

		if (mExe.length == 1) {
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

	override fn getTool(name: string) Command
	{
		c := name in mCommands;
		if (c is null) {
			return null;
		}
		return *c;
	}

	override fn addToolCmd(name: string, cmd: string)
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
		default:
			abort("unknown tool '%s' (%s)", name, cmd);
		}

		mCommands[name] = c;
	}

	override fn addToolArg(name: string, arg: string)
	{
		c := name in mCommands;
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
}
