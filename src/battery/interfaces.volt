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

	srcAsm: string[];
}

class Lib : Base
{
}

class Exe : Base
{
	bin: string;

	isDebug: bool;
	isInternalD: bool;

	srcC: string[];
	srcD: string[];
	srcObj: string[];
	srcVolt: string[];
}

class Command
{
	/// Textual name.
	name: string;
	/// Name and path.
	cmd: string;
	/// Extra args to give when invoking.
	args: string[];
	/// Name to print.
	print: string;
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

	/// Get a tool that has been added.
	abstract fn getTool(name: string) Command;

	/// Set a tool that has been found.
	abstract fn setTool(name: string, c: Command);

	/// Add a tool, will reset the tool if already given.
	abstract fn addToolCmd(name: string, cmd: string);

	/// Add a argument for tool.
	abstract fn addToolArg(name: string, arg: string);

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
