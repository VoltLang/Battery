// Copyright © 2016, Jakob Bornecrantz.  All rights reserved.
// See copyright notice in src/battery/license.volt (BOOST ver. 1.0).
module battery.configuration;

import watt.process : Environment;
public import battery.defines;
public import battery.interfaces;


enum LinkerKind
{
	Invalid,
	LD,    // LD
	GCC,   // GCC
	Link,  // MSVC
	Clang, // LLVM Clang
}

enum CCKind
{
	Invalid,
	CL,    // MSVC
	GCC,   // GCC
	Clang, // LLVM Clang
}

/**
 * A build configuration for one or more builds.
 *
 * This can be shared between multiple builds. When cross-compiling there will
 * be multiple configurations, one for the target and another for the host.
 */
class Configuration
{
public:
	env: Environment;
	isHost: bool;

	arch: Arch;
	platform: Platform;


	linkerCmd: Command;
	linkerKind: LinkerKind;

	ccCmd: Command;
	ccKind: CCKind;

	nasmCmd: Command;
	rdmdCmd: Command;
	dmdCmd: Command;

	commands: Command[string];


public:
	/// Get a tool that has been added.
	final fn getTool(name: string) Command
	{
		c := name in commands;
		if (c is null) {
			return null;
		}
		return *c;
	}

/*
	override fn addToolArg(name: string, arg: string)
	{
		c := getTool(host, name);
		if (c is null) {
			abort("tool not defined '%s'", name);
		}
		c.args ~= arg;
	}
*/
}
