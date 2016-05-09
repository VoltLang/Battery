// Copyright © 2012-2016, Jakob Bornecrantz.  All rights reserved.
// See copyright notice in src/battery/license.d (BOOST ver. 1.0).

/**
 * Here is the main solver algorithm implementation used as
 * a backend for all builds. Uses uni.util.cmd to dispatch
 * compilers and other tasks.
 */
module uni.core.solver;

import watt.io : output;
import watt.path : mkdirP, dirName;


import uni.core.target : Target, Rule;
import uni.util.cmd : CmdGroup;


/**
 * Builds a target, will throw exceptions on build failure.
 */
void build(Target t, uint numJobs)
{
	g := new CmdGroup(numJobs);
	built := build(t, g);
	if (built) {
		g.waitAll();
	}
}

/**
 * Internal recursive build function. Could be improved,
 * as every time the builder goes backup it waits for all
 * the children to complete building.
 */
private bool build(Target t, CmdGroup g)
{
	// This is needed for Windows.
	if (t.status < Target.CHECKED) {
		t.updateTime();
	}

	// Our work is allready done.
	if (t.status >= Target.BUILDING) {
		return t.status == Target.BUILDING ? true : false;
	}

	// Build all the dependancies.
	built := false;
	foreach (child; t.deps) {
		built = build(child, g) || built;
	}

	// XXX Figure out a better algorithm then this.
	if (built) {
		g.waitAll();
	}

	shouldBuild := false;
	foreach (d; t.deps) {
		// Kinda risky adding =,
		// but it avoids uneccasery recompiles.
		if (t.mod >= d.mod) {
			continue;
		}

		shouldBuild = true;
		break;
	}

	// All deps are older then this target, nothing to do.
	if (!shouldBuild) {
		return false;
	}

	/*
	 * Skip the file if we can't build it, in make this
	 * is an error, but that errors when you remove a
	 * file sometimes. If it actually is a error let the
	 * compiler warn about it.
	 */
	if (t.rule is null) {
		return false;
	}

	// Make sure the directory exist.
	mkdirP(dirName(t.name));

	// Print to console what we do.
	output.writefln(t.rule.print);
	output.flush();

	// The business end of the solver.
	t.status = Target.BUILDING;
	g.run(t.rule.cmd, t.rule.args, t.built, null);

	return true;
}
