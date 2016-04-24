// Copyright © 2016, Jakob Bornecrantz.  All rights reserved.
// See copyright notice in src/battery/license.volt (BOOST ver. 1.0).
module battery.compile;

import battery.defines;


class Target
{
	Arch arch;
	Platform platform;

	string[] defs;

	string outdir;

	uint hash;
}

class Volta
{
	string cmd;
}

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

string[] buildCmd(Volta v, Target t, Compile c)
{
	string[] ret = [
		v.cmd,
		"--no-stdlib",
		"--platform",
		t.platform.toString(),
		"--arch",
		t.arch.toString(),
		"-o",
		c.derivedTarget,
		"-I",
		c.srcRoot,
	];

	if (c.library) {
		ret ~= "-c";
	}

	foreach (d; t.defs) {
		ret ~= ["-D", d];
	}

	Compile[int] added;
	int[string] libs;

	void addDep(Compile c, bool root = false)
	{
		// Has this dep allready been added. 
		if (c.id in added) {
			return;
		}
		added[c.id] = c;

		if (root) {
			ret ~= ["-I", c.srcRoot];
		} else {
			ret ~= ["-I", c.srcRoot, c.derivedTarget];
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
