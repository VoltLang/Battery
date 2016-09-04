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
	name: string;
	bin: string;

	libs: string[];
	libPaths: string[];
	deps: string[];
	defs: string[];
	stringPaths: string[];

	xld: string[];
	xcc: string[];
	xlink: string[];
	xlinker: string[];

	srcDir: string;
}

class Lib : Base
{
}

class Exe : Base
{
	isDebug: bool;

	srcC: string[];
	srcObj: string[];
	srcVolt: string[];
}

abstract class Driver
{
public:
	/// Helper alias
	alias Fmt = watt.text.sink.SinkArg;


public:
	arch: Arch;
	platform: Platform;

	/// Normalize a path, target must exsist.
	abstract fn normalizePath(path: string) string;

	/// As the function name imples.
	abstract fn removeWorkingDirectoryPrefix(path: string) string;

	/// Add a executable
	abstract fn add(exe: Exe);

	/// Add a library
	abstract fn add(lib: Lib);

	/**
	 * Prints a action string.
	 *
	 * By default it is formated like this:
	 * "  BATTERY  <fmt>".
	 */
	abstract fn action(fmt: Fmt, ...);

	/**
	 * Prints a info string.
	 */
	abstract fn info(fmt: Fmt, ...);

	/**
	 * Error encoutered, print error then abort operation.
	 *
	 * May terminate program with exit, or throw an exception to resume.
	 */
	abstract fn abort(fmt: Fmt, ...);
}
