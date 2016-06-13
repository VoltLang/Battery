// Copyright © 2016, Jakob Bornecrantz.  All rights reserved.
// See copyright notice in src/battery/license.volt (BOOST ver. 1.0).
/**
 * Holds the default implementation of the Driver class.
 */
module battery.driver;

import core.stdc.stdlib : exit;
import io = watt.io;
import watt.varargs : va_list, va_start, va_end;

import battery.configuration;
import battery.interfaces;
import battery.policy.dir;
import battery.policy.cmd;


class DefaultDriver : Driver
{
protected:
	Configuration mHostConfig;
	Exe[] mExe;
	Lib[] mLib;


public:
	this()
	{

	}

	int process(string[] args)
	{
		if (args.length < 2) {
			printUsage();
		}

		switch (args[1]) {
		case "config": return config(args[2 .. $]);
		case "build": abort("not implement use config instead"); return 0;
		default: return printUsage();
		}

		return 0;
	}

	void get(out Lib[] lib, out Exe[] exe)
	{
		lib = mLib;
		exe = mExe;
	}

	int config(string[] args)
	{
		arg := new ArgParser(this);
		arg.parse(args, out mLib, out mExe);
		return 0;
	}

	int printUsage()
	{
		info("Battery, a package and build system for Volt pramming language.");
		info("");
		info("\tconfig [args]");
		info("\tbuild");
		return 0;
	}


	/*
	 *
	 * Driver functions.
	 *
	 */

	override void action(Fmt fmt, ...)
	{
		va_list vl;
		va_start(vl);
		io.output.write("  BATTERY  ");
		io.output.vwritefln(fmt, ref _typeids, ref vl);
		va_end(vl);
	}

	override void info(Fmt fmt, ...)
	{
		va_list vl;
		va_start(vl);
		io.output.vwritefln(fmt, ref _typeids, ref vl);
		va_end(vl);
	}

	override void abort(Fmt fmt, ...)
	{
		va_list vl;
		va_start(vl);
		io.output.write("error: ");
		io.output.vwritefln(fmt, ref _typeids, ref vl);
		va_end(vl);
		exit(-1);
	}
}
