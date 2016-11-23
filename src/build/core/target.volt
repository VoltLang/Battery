// Copyright © 2012-2016, Jakob Bornecrantz.  All rights reserved.
// See copyright notice in src/battery/license.d (BOOST ver. 1.0).

/**
 * The basic building blocks for a build.
 */
module build.core.target;

import core.exception;
import watt.io.file : exists;
import watt.text.string : indexOf;
import watt.text.format : format;
import build.util.file : getTimes;


/**
 * Holds all inspected files/targets for a build. The caching supplied
 * by this class helps with both speed and ease of use.
 */
final class Instance
{
private:
	targets: Target[string];

public:
	fn file(name: string) Target
	{
		// Make sure they all have the same path.
		version (Windows) {
			assert(indexOf(name, '/') < 0, name);
		}

		test := name in targets;
		if (test !is null) {
			return *test;
		}

		ret := new Target();
		ret.name = name;
		return targets[name] = ret;
	}

	fn fileNoRule(name: string) Target
	{
		ret := file(name);
		if (ret.rule !is null) {
			str := format("File \"%s\" already has a rule", name);
			throw new Exception(str);
		}

		return ret;
	}
}

/**
 * Most basic building block, represent a single file on the file
 * system. Can be used as a dependency and as a target to be built.
 */
final class Target
{
public:
	enum Status {
		FRESH,
		CHECKED,
		BLOCKED,
		BUILDING,
		BUILT
	}

	alias FRESH    = Status.FRESH;
	alias CHECKED  = Status.CHECKED;
	alias BLOCKED  = Status.BLOCKED;
	alias BUILDING = Status.BUILDING;
	alias BUILT    = Status.BUILT;

	/// What is the status of this target.
	/// Used to skip updating the date.
	status: Status;

	/// Name, for file also actuall filename.
	name: string;

	/// Rule to build this targe.
	rule: Rule;

	/// Will be built, but if no rule and missing will be ignored.
	deps: Target[];

	/// Cached last modified time.
	mod: ulong;

public:
	/// Updates the @mod field to the files last modified time.
	fn updateTime()
	{
		// Somebody might have set a higher status.
		if (status <= FRESH) {
			status = CHECKED;
		}

		if (!exists(name)) {
			mod = ulong.min;
		} else {
			a : ulong;
			getTimes(name, out a, out mod);
		}
	}

	/**
	 * Called by the solver when the target has been built.
	 */
	fn built()
	{
		updateTime();
		status = BUILT;
	}
}

/**
 * Rule to be executed. Can be shared for multiple targets.
 */
final class Rule
{
public:
	/// To run be executed.
	cmd: string;

	/// To be given to cmd.
	args: string[];

	/// Echoed to stdout.
	print: string;

	/// Files needed directly to run this rule.
	input: Target[];

	/// When the rule is running these targets will be locked.
	outputs: Target[];

public:
	/**
	 * Called by the solver when the target has been built.
	 */
	fn built(retval: i32)
	{
		if (retval != 0) {
			throw new Exception(format("command '%s' aborted with non-zero retval %s", cmd, retval));
		}
		foreach (o; outputs) {
			o.built();
		}
	}
}
