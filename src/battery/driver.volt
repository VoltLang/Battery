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
		case "config": return scan(args[2 .. $]);
		case "build": return build(args[2 .. $]);
		default: return printUsage();
		}

		return 0;
	}

	void get(out Lib[] lib, out Exe[] exe)
	{
		lib = mLib;
		exe = mExe;
	}

	int scan(string[] dirs)
	{
		foreach (dir; dirs) {

			ret := scanDir(this, dir);
			exe := cast(Exe)ret;
			lib := cast(Lib)ret;

			if (exe !is null) {
				mExe ~= exe;
			} else if (lib !is null) {
				mLib ~= lib;
			} else {
				abort("internal error");
			}
		}

		foreach (exe; mExe) {
			foreach (lib; mLib) {
				exe.deps ~= lib.name;
			}
		}

		return 0;
	}

	int build(string[] args)
	{
		// TODO save config to disk and read here.
		scan(args);

		return 0;
	}

	int printUsage()
	{
		info("Battery, a package and build system for Volt pramming language.");
		info("");
		info("\tconfig [dirs]");
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
