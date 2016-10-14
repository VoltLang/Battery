// Copyright © 2016, Jakob Bornecrantz.  All rights reserved.
// See copyright notice in src/battery/license.volt (BOOST ver. 1.0).
/**
 * Companion module to battery.policy.cmd.
 */
module battery.policy.arg;

import battery.interfaces;


/**
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

		Command,

		Library,
		LibraryPath,

		StringPath,

		Debug,
		InternalD,
		Identifier,
		Output,

		FileC,
		FileD,
		FileObj,
		FileAsm,
		FileVolt,

		ArgLD,
		ArgCC,
		ArgLink,
		ArgLinker,

		ToolCmd,
		ToolArg,
	}

	/// Always set, often the original param.
	flag: string;

	/// Extra option to the flag.
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
