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

		Library,
		LibraryPath,

		Debug,
		Identifier,
		Output,

		FileC,
		FileObj,
		FileVolt,
	}

	string flag;
	string extra;

	int condArch;
	int condPlatform;

	Kind kind;

public:
	this(Kind kind, string flag)
	{
		this.kind = kind;
		this.flag = flag;
	}

	this(Kind kind, string flag, string extra)
	{
		this.kind = kind;
		this.flag = flag;
		this.extra = extra;
	}

	void addArch(int bits)
	{
		condArch |= bits;
	}

	void addPlatform(int bits)
	{
		condPlatform |= bits;
	}
}

void filterArgs(ref Arg[] args, Arch arch, Platform platform)
{
	size_t pos;

	foreach (arg; args) {
		if (arg.condArch && !(arg.condArch & (1 << arch))) {
			continue;
		}

		if (arg.condPlatform && !(arg.condPlatform & (1 << platform))) {
			continue;
		}

		// Its okay to let this one trough.
		args[pos++] = arg;
	}

	// Update length
	args = args[0 .. pos];
}
