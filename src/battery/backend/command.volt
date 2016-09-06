// Copyright © 2016, Jakob Bornecrantz.  All rights reserved.
// See copyright notice in src/battery/license.volt (BOOST ver. 1.0).
module battery.backend.command;

import battery.interfaces;
import battery.configuration;


struct ArgsGenerator
{
public:
	libs: Lib[];
	exes: Exe[];
	store: Base[string];
	voltaArgs: string[];
	archStr: string;
	platformStr: string;


public:
	fn setup(config: Configuration, libs: Lib[], exes: Exe[])
	{
		this.libs = libs;
		this.exes = exes;
		this.store = [];

		this.archStr = .toString(config.arch);
		this.platformStr = .toString(config.platform);

		this.voltaArgs = [
			"--no-stdlib",
			"--platform", platformStr,
			"--arch", archStr,
			getLinkerFlag(config),
			config.linkerCmd,
		];

		foreach (lib; libs) {
			store[lib.name] = lib;
		}

		foreach (exe; exes) {
			store[exe.name] = exe;
		}
	}

	/**
	 * Generates a Volta command line to build a binary.
	 */
	fn genVoltaArgs(base: Base) string[]
	{
		added: Base[string];
		exe := cast(Exe)base;

		// Copy the default command line.
		ret := voltaArgs;

		fn traverse(b: Base, first: bool = false)
		{
			// Has this dep allready been added.
			p := b.name in added;
			if (p !is null) {
				return;
			}

			// Keep track of it now.
			added[b.name] = b;

			if (first || b.bin is null) {
				ret ~= ["--src-I", b.srcDir];
			} else {
				ret ~= b.bin;
				ret ~= ["--lib-I", b.srcDir];
			}

			foreach (path; b.libPaths) {
				ret ~= ["-L", path];
			}

			foreach (path; b.stringPaths) {
				ret ~= ["-J", path];
			}

			foreach (lib; b.libs) {
				ret ~= ["-l", lib];
			}

			foreach (def; b.defs) {
				ret ~= ["-D", def];
			}

			foreach (arg; b.xcc) {
				ret ~= ["--Xcc", arg];
			}

			foreach (arg; b.xlink) {
				ret ~= ["--Xlink", arg];
			}

			foreach (arg; b.xlinker) {
				ret ~= ["--Xlinker", arg];
			}

			foreach (dep; b.deps) {
				traverse(store[dep]);
			}
		}

		traverse(base, base !is null);

		// Implictly add rt as a dependancy
		traverse(store["rt"]);

		// Set debug.
		if (exe !is null && exe.isDebug) {
			ret ~= "-d";
		}

		return ret;
	}


private:
	fn getLinkerFlag(config: Configuration) string
	{
		final switch (config.linkerKind) with (LinkerKind) {
		case LD: return "--ld";
		case GCC: return "--cc";
		case Link: return "--link";
		case Clang: return "--cc";
		case Invalid: assert(false);
		}
	}
}
