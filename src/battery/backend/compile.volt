// Copyright © 2016, Jakob Bornecrantz.  All rights reserved.
// See copyright notice in src/battery/license.volt (BOOST ver. 1.0).
module battery.backend.compile;

import battery.defines;
import battery.configuration;


class Compile
{
	string name;
	string srcRoot;
	string[] src;
	Compile[] deps;
	bool library;

	int id;

	string derivedTarget;
	string[] libs;

private:
	global int mCount;

public:
	this()
	{
		this.id = mCount++;
	}
}

string[] buildCmd(Configuration config, Compile c)
{
	string[] ret = [
		config.volta.cmd,
		"--no-stdlib",
		"--platform",
		config.platform.toString(),
		"--arch",
		config.arch.toString(),
		config.linker.flag,
		config.linker.cmd,
		"-o",
		c.derivedTarget
	];

	if (config.isDebug) {
		ret ~= "-d";
	}

	if (c.library) {
		ret ~= "-c";
	}

	foreach (d; config.defs) {
		ret ~= ["-D", d];
	}

	// Make sure a Compile (library) is only added once.
	Compile[int] added;

	// Make sure a external library is only given to the linker once.
	int[string] libs;


	void addDep(Compile c, bool root = false)
	{
		// Has this dep allready been added. 
		if (c.id in added) {
			return;
		}
		added[c.id] = c;

		if (root || c.derivedTarget is null) {
			ret ~= ["--src-I", c.srcRoot];
		} else {
			ret ~= ["--lib-I", c.srcRoot, c.derivedTarget];
		}

		foreach (l; c.libs) {
			libs[l] = 0;
		}

		// Add all child deps of this dep.
		foreach (d; c.deps) {
			addDep(d);
		}
	}

	addDep(c, true);

	foreach (l; libs.keys) {
		ret ~= ["-l", l];
	}

	ret ~= c.src;

	return ret;
}
