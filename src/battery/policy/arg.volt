// Copyright 2016-2018, Jakob Bornecrantz.
// SPDX-License-Identifier: BSL-1.0
/*!
 * Companion module to battery.policy.cmd.
 */
module battery.policy.arg;

import battery.commonInterfaces;


/*!
 * Class for argument processing.
 */
class Arg
{
public:
	enum Kind
	{
		Directory,

		Exe,
		Lib,

		Name,
		Dep,
		SrcDir,
		TestFile,

		Command,

		WarningsEnabled,

		Library,
		LibraryPath,

		Framework,
		FrameworkPath,

		StringPath,

		IsTheRT,
		ScanForD,
		Identifier,
		Output,
		JSONOutput,

		FileC,
		FileD,
		FileS,
		FileObj,
		FileAsm,
		FileVolt,

		ArgLD,
		ArgCC,
		ArgLink,
		ArgLinker,

		Env,
		BootEnv,
		HostEnv,

		ToolCmd,
		ToolArg,
		BootToolCmd,
		BootToolArg,
		HostToolCmd,
		HostToolArg,
	}

	//! Always set, often the original param.
	flag: string;

	//! Extra option to the flag.
	extra: string;

	condArch: int;
	condPlatform: int;

	kind: Kind;


public:
	this(kind: Kind, flag: string)
	{
		this.kind = kind;
		this.flag = flag;
	}

	this(kind: Kind, flag: string, extra: string)
	{
		this.kind = kind;
		this.flag = flag;
		this.extra = extra;
	}
}

fn filterArgs(ref args: Arg[], arch: Arch, platform: Platform)
{
	pos: size_t;
	archBits := (1 << arch);
	platformBits := (1 << platform);

	foreach (arg; args) {
		if (arg.condArch && !(arg.condArch & archBits)) {
			continue;
		}

		if (arg.condPlatform && !(arg.condPlatform & platformBits)) {
			continue;
		}

		// Its okay to let this one trough.
		args[pos++] = arg;
	}

	// Update length
	args = args[0 .. pos];
}
