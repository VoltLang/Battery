// Copyright © 2016, Jakob Bornecrantz.  All rights reserved.
// See copyright notice in src/battery/license.volt (BOOST ver. 1.0).
module battery.configuration;

import core.exception;

import watt.process : Environment;
public import battery.defines;
public import battery.interfaces;


enum LinkerKind
{
	Invalid,
	Link,  // MSVC
	Clang, // LLVM Clang
}

enum CCKind
{
	Invalid,
	Clang, // LLVM Clang
}

enum ConfigKind
{
	Invalid,
	Native,
	Host,
	Cross,
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
	kind: ConfigKind;

	arch: Arch;
	platform: Platform;
	isRelease: bool;
	isLTO: bool;

	clangCmd: Command;

	linkerCmd: Command;
	linkerKind: LinkerKind;

	ccCmd: Command;
	ccKind: CCKind;

	nasmCmd: Command;
	rdmdCmd: Command;
	dmdCmd: Command;

	tools: Command[string];


public:
	/// Get a tool that has been added.
	final fn getTool(name: string) Command
	{
		c := name in tools;
		if (c is null) {
			return null;
		}
		return *c;
	}

	final fn addTool(name: string, cmd: string, args: string[]) Command
	{
		c := getTool(name);
		if (c !is null) {
			throw new Exception("redefining tool '%s'", name);
		}
		c = new Command();
		c.name = name;
		c.cmd = cmd;
		c.args = args;
		tools[name] = c;

		return c;
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

	@property final fn isNative() bool { return kind == ConfigKind.Native; }
	@property final fn isHost() bool { return kind == ConfigKind.Host; }
	@property final fn isCross() bool { return kind == ConfigKind.Cross; }
}
