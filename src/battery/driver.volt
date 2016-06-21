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
import watt.process : getEnv;

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
		case "config": return config(args[2 .. $]);
		case "build": return build(args[2 .. $]);
		default: return printUsage();
		}
	}

	void get(out Lib[] lib, out Exe[] exe)
	{
		lib = mLib;
		exe = mExe;
	}

	void config(string[] args)
	{
		arg := new ArgParser(this);
		arg.parse(args);
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

		path := getEnv("PATH");
		config := getHostConfig(path);
		builder := new Builder(this);
		builder.build(config, mLib, mExe);
	}

	void printUsage()
	{
		info("Battery, a package and build system for Volt pramming language.");
		info("");
		info("\tconfig [args]");
		info("\tbuild");
	}


	/*
	 *
	 * Driver functions.
	 *
	 */

	override void add(Lib lib)
	{
		mLib ~= lib;
	}

	override void add(Exe exe)
	{
		mExe ~= exe;
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
