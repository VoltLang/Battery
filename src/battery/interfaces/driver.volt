// Copyright 2016-2018, Jakob Bornecrantz.
// Copyright 2021, Collabora Inc.
// SPDX-License-Identifier: BSL-1.0
/*!
 * Interface to the driver.
 */
module battery.interfaces.driver;

static import watt.text.sink;
public import battery.defines;
import battery.interfaces.project;


/*!
 * Interface to the main class that controles the entire process.
 */
abstract class Driver
{
public:
	//! Helper alias
	alias Fmt = watt.text.sink.SinkArg;


public:
	arch: Arch;
	platform: Platform;

	//! Normalise a path, target must exsist.
	abstract fn normalisePath(path: string) string;

	//! As the function name imples.
	abstract fn removeWorkingDirectoryPrefix(path: string) string;

	//! Add a executable
	abstract fn add(exe: Exe);

	//! Add a library
	abstract fn add(lib: Lib);

	//! Add a enviromental variable.
	abstract fn addEnv(boot: bool, name: string, value: string);

	//! Set a tool that has been found.
	abstract fn setCmd(boot: bool, name: string, c: Command);

	//! Get a tool.
	abstract fn getCmd(boot: bool, name: string) Command;

	//! Add a tool, will reset the tool if already given.
	abstract fn addCmd(boot: bool, name: string, cmd: string);

	//! Add a argument for tool.
	abstract fn addCmdArg(boot: bool, name: string, arg: string);

	/*!
	 * Prints a action string.
	 *
	 * By default it is formated like this:
	 *
	 * ```
	 *   BATTERY  <fmt>
	 * ```
	 * @param fmt The format string, same formatting as @ref watt.text.format.
	 */
	abstract fn action(fmt: Fmt, ...);

	/*!
	 * Prints a info string.
	 *
	 * @param fmt The format string, same formatting as @ref watt.text.format.
	 */
	abstract fn info(fmt: Fmt, ...);

	/*!
	 * Error encoutered, print error then abort operation.
	 *
	 * May terminate program with exit, or throw an exception to resume.
	 *
	 * @param fmt The format string, same formatting as @ref watt.text.format.
	 */
	abstract fn abort(fmt: Fmt, ...);
}
