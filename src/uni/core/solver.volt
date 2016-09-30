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
import watt.process;

import uni.core.target : Target, Rule;
import uni.util.cmd : CmdGroup;


/**
 * Builds a target, will throw exceptions on build failure.
 */
fn build(t: Target, numJobs: uint, env: Environment)
{
	g := new CmdGroup(env, numJobs);
	build(t, g);
}

/**
 * Internal looping build function.
 */
private fn build(root: Target, g: CmdGroup)
{
	shouldRestart := true;
	while (shouldRestart) {
		shouldRestart = false;
		build(root, g, ref shouldRestart);

		// Wait untill at least on dependancy has been solved.
		g.waitOne();
	}
}

/**
 * Internal recursive build function.
 */
private fn build(t: Target, g: CmdGroup, ref shouldRestart: bool)
{
	// If the target is fresh check it,
	// checking this helps for performance on Windows.
	if (t.status < Target.CHECKED) {
		t.updateTime();
	}

	// This target is already building or have been built,
	// then we don't need to do anything more.
	if (t.status >= Target.BUILDING) {
		return;
	}

	// Make sure all dependancies are built.
	foreach (child; t.deps) {
		build(child, g, ref shouldRestart);
	}

	// Then check if we should build this target.
	shouldBuild := false;
	foreach (d; t.deps) {

		if (d.status < Target.BUILT) {
			assert(d.status == Target.BUILDING ||
			       d.status == Target.BLOCKED);
			shouldRestart = true;
			t.status = Target.BLOCKED;
			return;
		}

		// Kinda risky adding =,
		// but it avoids uneccasery recompiles.
		if (t.mod >= d.mod) {
			continue;
		}

		shouldBuild = true;
	}

	// All deps are older then this target, mark it as built.
	if (!shouldBuild) {
		t.status = Target.BUILT;
		return;
	}

	/*
	 * Skip the file if we can't build it, in make this
	 * is an error, but that errors when you remove a
	 * file sometimes. If it actually is a error let the
	 * compiler warn about it.
	 */
	if (t.rule is null) {
		return;
	}

	// Make sure the directory exist.
	foreach (o; t.rule.outputs) {
		mkdirP(dirName(o.name));
		o.status = Target.BUILDING;
	}

	// Print to console what we do.
	output.writefln(t.rule.print);
	output.flush();

	// The business end of the solver.
	g.run(t.rule.cmd, t.rule.args, t.rule.built, null);

	return;
}
