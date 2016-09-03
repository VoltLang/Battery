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
	store: Lib[string];


public:
	fn setup(libs: Lib[], exes: Exe[])
	{
		this.libs = libs;
		this.exes = exes;
		this.store = [];

		foreach (lib; libs) {
			store[lib.name] = lib;
		}
	}

	fn genCommandLine(base: Base) string[]
	{
		added: Base[string];
		ret: string[];
		exe := cast(Exe)base;

		fn traverse(b: Base, first: bool = false)
		{
			// Has this dep allready been added.
			auto p = b.name in added;
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
}
