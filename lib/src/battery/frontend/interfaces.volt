// Copyright 2016-2018, Jakob Bornecrantz.
// SPDX-License-Identifier: BSL-1.0
/*!
 * Contians common classes and code for objects going into the frontend.
 */
module battery.frontend.interfaces;

import battery.defines;


/*!
 * A semi-resolved object for either a exe, lib or container.
 */
final class Project
{
	//! Source folder path.
	srcPath: string;

	//! The contents of the found file.
	tomlFile: string;

	//! Arguments from command line for this project.
	givenArgs: string[];
}

/*!
 * A build configuration for one or more builds.
 *
 * This can be shared between multiple builds. When cross-compiling there will
 * be multiple configurations, one for the target and another for the host.
 */
final class Configuration
{
public:
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

	//! Given commands.
	givenCommands: Command[string];


public:
	//! Helper properties. @{
	@property final fn isBootstrap() bool { return kind == ConfigKind.Bootstrap; }
	@property final fn isNative() bool { return kind == ConfigKind.Native; }
	//@property final fn isHost() bool { return kind == ConfigKind.Host; }
	@property final fn isCross() bool { return kind == ConfigKind.Cross; }
	//! @}
}
