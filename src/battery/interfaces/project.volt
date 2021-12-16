// Copyright 2016-2018, Jakob Bornecrantz.
// Copyright 2021, Collabora Inc.
// SPDX-License-Identifier: BSL-1.0
/*!
 * Main interfaces for code of battery.
 */
module battery.interfaces.project;


/*!
 * A single project can either be a @ref Lib or @ref Exe.
 */
class Project
{
	name: string;
	batteryToml: string;

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
	srcS: string[];
	srcObj: string[];
	srcAsm: string[];

	testFiles: string[];


	//! Was this target given a -jo argument.
	jsonOutput: string;

	//! Should we ignore this project unless explicitly asked for
	isExternal: bool;

	//! For D projects.
	scanForD: bool;

	//! Hack to add LLVMVersionX versions.
	llvmHack: bool;

	warningsEnabled: bool;
}

//! The project is built as a library used by executables.
class Lib : Project
{
	isTheRT: bool;
}

//! The project is built as a executable.
class Exe : Project
{
	bin: string;

	srcVolt: string[];
}
