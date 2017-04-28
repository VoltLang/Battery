// Copyright © 2016, Jakob Bornecrantz.  All rights reserved.
// See copyright notice in src/battery/license.volt (BOOST ver. 1.0).
/**
 * Path helpers.
 */
module battery.util.path;

import watt.path : pathSeparator, dirSeparator, exists;
import watt.process : Environment;
import watt.text.path : normalizePath, makePathAppendable;
import watt.text.format : format;
import watt.text.string : replace, split, endsWith;


fn cleanPath(s: string) string
{
	return normalizePath(makePathAppendable(s));
}

fn searchPath(cmd: string, env: Environment) string
{
	path := env.getOrNull("PATH");
	assert(path !is null);
	assert(pathSeparator.length == 1);

	fmt := "%s%s%s";
	version (Windows) if (!endsWith(cmd, ".exe")) {
		fmt = "%s%s%s.exe";
	}

	foreach (p; split(path, pathSeparator[0])) {
		t := format(fmt, p, dirSeparator, cmd);
		if (exists(t)) {
			return t;
		}
	}

	return null;
}
