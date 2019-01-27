// Copyright 2016-2018, Jakob Bornecrantz.
// SPDX-License-Identifier: BSL-1.0
/*!
 * Contians the per build configuration.
 */
module battery.configuration;

import core.exception;

import semver = watt.text.semver;
import watt.process : Environment;
public import battery.defines;
public import battery.commonInterfaces;


/*!
 * A build configuration for one or more builds.
 *
 * This can be shared between multiple builds. When cross-compiling there will
 * be multiple configurations, one for the target and another for the host.
 */
final class Configuration
{
public:
	//! Used when launching commands.
	env: Environment;
	//! Is this, native, host or cross-compile?
	kind: ConfigKind;

	//! Architecture for this configuration.
	arch: Arch;
	//! Platform for this configuration.
	platform: Platform;
	//! Is the build release or debug.
	isRelease: bool;
	//! Link-time-optimizations, implemented via LLVM's ThinLTO.
	isLTO: bool;
	//! Should we generate vdoc json files.
	shouldJSON: bool;

	//! The llvmConf path, given by --llvmconf.
	llvmConf: string;

	//! The battery config file that might be loaded.
	batConf: BatteryConfig;

	//! LLVM version.
	llvmVersion: semver.Release;

	//! Base clang command.
	clangCmd: Command;

	//! Linker command. @{
	linkerCmd: Command;
	linkerKind: LinkerKind;
	//! @}

	//! C-compiler. @{
	ccCmd: Command;
	ccKind: CCKind;
	//! @}

	//! NASM used for rt assembly files.
	nasmCmd: Command;

	//! Rdmd for bootstrapping.
	rdmdCmd: Command;

	//! Gdc for bootstrapping.
	gdcCmd: Command;

	//! All added tools.
	tools: Command[string];


public:
	//! Get a tool that has been added.
	final fn getTool(name: string) Command
	{
		c := name in tools;
		if (c is null) {
			return null;
		}
		return *c;
	}

	/*!
	 * Adds a tool to this configuration,
	 * a given tool can only be added once.
	 */
	final fn addTool(name: string, cmd: string, args: string[]) Command
	{
		c := getTool(name);
		if (c !is null) {
			throw new Exception(new "redefining tool ${name}");
		}
		c = new Command();
		c.name = name;
		c.cmd = cmd;
		c.args = args;
		tools[name] = c;

		return c;
	}

	//! Helper properties. @{
	@property final fn isBootstrap() bool { return kind == ConfigKind.Bootstrap; }
	@property final fn isNative() bool { return kind == ConfigKind.Native; }
	//@property final fn isHost() bool { return kind == ConfigKind.Host; }
	@property final fn isCross() bool { return kind == ConfigKind.Cross; }
	//! @}
}
