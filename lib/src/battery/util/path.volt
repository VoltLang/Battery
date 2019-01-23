// Copyright 2016-2018, Jakob Bornecrantz.
// SPDX-License-Identifier: BSL-1.0
/*!
 * Path helpers.
 */
module battery.util.path;

import watt.path : pathSeparator, dirSeparator, exists;
import watt.io.file : isFile;
import watt.text.path : normalisePath, makePathAppendable;
import watt.text.format : format;
import watt.text.string : replace, split, endsWith;
import battery.util.log : Logger;


fn cleanPath(s: string) string
{
	return normalisePath(makePathAppendable(s));
}

fn searchPath(path: string, cmd: string) string
{
	if (path is null) {
		return null;
	}

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

fn checkArgCmd(ref log: Logger, cmd: string, name: string) bool
{
	if (cmd is null) {
		return false;
	}

	if (isFile(cmd)) {
		return true;
	}

	log.info(new "The ${name} command given as '${cmd}' does not exists!");
	return false;
}
