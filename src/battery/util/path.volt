// Copyright © 2016, Jakob Bornecrantz.  All rights reserved.
// See copyright notice in src/battery/license.volt (BOOST ver. 1.0).
module battery.util.path;

import watt.text.string : split;
import watt.process : getEnv;
import watt.path : dirSeparator, pathSeparator;
import watt.io.file : exists;


string searchPath(string cmd, string path = null)
{
	if (path is null) {
		path = getEnv("PATH");
	}
	if (path is null) {
		return null;
	}

	assert(pathSeparator.length == 1);

	foreach (p; split(path, pathSeparator[0])) {
		t := p ~ dirSeparator ~ cmd;
		if (exists(t)) {
			return t;
		}
	}

	return null;
}
