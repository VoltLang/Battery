// Copyright 2012-2018, Jakob Bornecrantz.
// SPDX-License-Identifier: BSL-1.0
/*!
 * Here is the main solver algorithm implementation used as
 * a backend for all builds. Uses build.util.cmd to dispatch
 * compilers and other tasks.
 */
module build.core.solver;

import watt.io : output;
import watt.path : mkdirP, dirName;
import watt.process;

import build.core.target : Target, Rule;
import build.util.cmdgroup : CmdGroup;


/*!
 * Builds a target, will throw exceptions on build failure.
 */
fn doBuild(t: Target, numJobs: uint, env: Environment, verbose: bool)
{
	g := new CmdGroup(env, numJobs);
	build(t, g, verbose);
}

/*!
 * Internal looping build function.
 */
private fn build(root: Target, g: CmdGroup, verbose: bool)
{
	shouldRestart := true;
	while (shouldRestart) {
		shouldRestart = false;
		build(root, g, verbose, ref shouldRestart);

		// Wait untill at least on dependancy has been solved.
		g.waitOne();
	}
}

/*!
 * Internal recursive build function.
 */
private fn build(t: Target, g: CmdGroup, verbose: bool, ref shouldRestart: bool)
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
		build(child, g, verbose, ref shouldRestart);
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
	if (verbose) {
		output.writeln(new "${[t.rule.cmd] ~ t.rule.args}\n");
	}
	output.flush();

	// The business end of the solver.
	g.run(t.rule.cmd, t.rule.args, t.rule.built, null);

	return;
}
