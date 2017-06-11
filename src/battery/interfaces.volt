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
	frameworks: string[];
	frameworkPaths: string[];
	deps: string[];
	defs: string[];
	stringPaths: string[];

	xld: string[];
	xcc: string[];
	xlink: string[];
	xlinker: string[];

	srcDir: string;

	srcC: string[];
	srcObj: string[];
	srcAsm: string[];

	testDirs: string[];
}

class Lib : Base
{
}

class Exe : Base
{
	bin: string;

	isInternalD: bool;

	srcD: string[];
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

	this()
	{
	}

	this(cmd: string, args: string[])
	{
		this.cmd = cmd;
		this.args = args;
	}

	this(name: string, c: Command)
	{
		this.name = name;
		this.cmd = c.cmd;
		this.print = c.print;
		this.args = new string[](c.args);
	}
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

	/// Add a enviromental variable.
	abstract fn addEnv(host: bool, name: string, value: string);

	/// Set a tool that has been found.
	abstract fn setCmd(host: bool, name: string, c: Command);

	/// Get a tool.
	abstract fn getCmd(host: bool, name: string) Command;

	/// Add a tool, will reset the tool if already given.
	abstract fn addCmd(host: bool, name: string, cmd: string);

	/// Add a argument for tool.
	abstract fn addCmdArg(host: bool, name: string, arg: string);

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
