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
static import battery.interfaces.driver;


/*!
 * Interface to the main class that controles the entire process.
 */
abstract class Driver : battery.interfaces.Driver
{
public:
	arch: Arch;
	platform: Platform;


public:
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
}
