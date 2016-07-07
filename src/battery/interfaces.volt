// Copyright © 2016, Jakob Bornecrantz.  All rights reserved.
// See copyright notice in src/battery/license.volt (BOOST ver. 1.0).
/**
 * Main interfaces for code of battery.
 */
module battery.interfaces;

static import watt.text.sink;
public import battery.defines;


class Base
{
	string name;
	string bin;

	string[] libs;
	string[] libPaths;
	string[] deps;
	string[] defs;
	string[] stringPaths;

	string[] xld;
	string[] xcc;
	string[] xlink;
	string[] xlinker;

	string srcDir;
}

class Lib : Base
{
}

class Exe : Base
{
	bool isDebug;

	string[] srcC;
	string[] srcObj;
	string[] srcVolt;
}

abstract class Driver
{
public:
	/// Helper alias
	alias Fmt = watt.text.sink.SinkArg;


public:
	Arch arch;
	Platform platform;

	/// Normalize a path, target must exsist.
	abstract string normalizePath(string path);

	/// As the function name imples.
	abstract string removeWorkingDirectoryPrefix(string path);

	/// Add a executable
	abstract void add(Exe exe);

	/// Add a library
	abstract void add(Lib lib);

	/**
	 * Prints a action string.
	 *
	 * By default it is formated like this:
	 * "  BATTERY  <fmt>".
	 */
	abstract void action(Fmt fmt, ...);

	/**
	 * Prints a info string.
	 */
	abstract void info(Fmt fmt, ...);

	/**
	 * Error encoutered, print error then abort operation.
	 *
	 * May terminate program with exit, or throw an exception to resume.
	 */
	abstract void abort(Fmt fmt, ...);
}
