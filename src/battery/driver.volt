// Copyright © 2016, Jakob Bornecrantz.  All rights reserved.
// See copyright notice in src/battery/license.volt (BOOST ver. 1.0).
/**
 * Holds the default implementation of the Driver class.
 */
module battery.driver;

import core.stdc.stdlib : exit;
import io = watt.io;
import watt.io.streams : OutputFileStream;
import watt.varargs : va_list, va_start, va_end;

import battery.configuration;
import battery.interfaces;
import battery.policy.dir;
import battery.policy.cmd;
import battery.policy.host;
import battery.util.file : getLinesFromFile;
import battery.backend.build;


class DefaultDriver : Driver
{
public:
	enum BatteryConfigFile = ".battery.config.txt";


protected:
	Configuration mHostConfig;
	Base[string] mStore;
	Exe[] mExe;
	Lib[] mLib;


public:
	this()
	{
		arch = HostArch;
		platform = HostPlatform;
	}

	void process(string[] args)
	{
		switch (args.length) {
		case 1: return build(null);
		default:
		}

		switch (args[1]) {
		case "help": return help(args[2 .. $]);
		case "build": return build(args[2 .. $]);
		case "config": return config(args[2 .. $]);
		default: return printUsage();
		}
	}

	void config(string[] args)
	{
		// Get host config
		mHostConfig := getHostConfig();

		arg := new ArgParser(this);
		arg.parse(args);

		verifyConfig();

		ret := getArgs(mLib, mExe);

		ofs := new OutputFileStream(BatteryConfigFile)
		foreach (r; ret) {
			ofs.write(r);
			ofs.put('\n');
		}
		ofs.flush();
		ofs.close();
	}

	void build(string [] args)
	{
		args = null;
		if (!getLinesFromFile(BatteryConfigFile, ref args)) {
			return abort("must first run the 'config' command");
		}

		arg := new ArgParser(this);
		arg.parse(args);

		mHostConfig := getHostConfig();
		builder := new Builder(this);
		builder.build(mHostConfig, mLib, mExe);
	}

	void help(string[] args)
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

	void printUsage()
	{
		info("Battery, a package and build system for Volt pramming language.");
		info("");
		info("\thelp <command>");
		info("\tconfig [directories|args]");
		info("\tbuild");
	}

	void printHelpUsage()
	{
		info("This is where the help for 'help' goes.");
	}

	void printBuildUsage()
	{
		info("This is where the help for 'build' goes.");
	}

	void printConfigUsage()
	{
		info("This is where the help for 'config' goes.");
	}


	/*
	 *
	 * Verifying the condig.
	 *
	 */

	void verifyConfig()
	{
		rt := mStore.get("rt", null);
		volta := mStore.get("volta", null);
		if (volta is null) {
			abort("Must specify a Volta directory (for now).");
		}
		if (rt is null) {
			abort("Must specify a Volta directory (for now).");
		}

		if (mHostConfig.linker.cmd is null) {
			abort("No system linker found.");
		}
		if (mHostConfig.cc.cmd is null) {
			abort("No system c compiler found.");
		}
		if (mHostConfig.rdmd.rdmd is null) {
			abort("No rdmd found (needed right now for Volta).");
		}
		if (mHostConfig.rdmd.dmd is null) {
			abort("No dmd found (needed right now for Volta).");
		}
	}


	/*
	 *
	 * Driver functions.
	 *
	 */

	override void add(Lib lib)
	{
		if (mStore.get(lib.name, null) !is null) {
			abort("Executable or Library with name '%s' already defined.", lib.name);
		}

		mLib ~= lib;
		mStore[lib.name] = lib;
	}

	override void add(Exe exe)
	{
		if (mStore.get(exe.name, null) !is null) {
			abort("Executable or Library with name '%s' already defined.", exe.name);
		}

		mExe ~= exe;
		mStore[exe.name] = exe;
	}

	override void action(Fmt fmt, ...)
	{
		va_list vl;
		va_start(vl);
		io.output.write("  BATTERY  ");
		io.output.vwritefln(fmt, ref _typeids, ref vl);
		io.output.flush();
		va_end(vl);
	}

	override void info(Fmt fmt, ...)
	{
		va_list vl;
		va_start(vl);
		io.output.vwritefln(fmt, ref _typeids, ref vl);
		io.output.flush();
		va_end(vl);
	}

	override void abort(Fmt fmt, ...)
	{
		va_list vl;
		va_start(vl);
		io.output.write("error: ");
		io.output.vwritefln(fmt, ref _typeids, ref vl);
		io.output.flush();
		va_end(vl);
		exit(-1);
	}
}
