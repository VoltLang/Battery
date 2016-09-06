// Copyright © 2016, Jakob Bornecrantz.  All rights reserved.
// See copyright notice in src/battery/license.volt (BOOST ver. 1.0).
/**
 * File helpers.
 */
module battery.util.file;

import watt.text.string : splitLines;
import watt.io.file : exists, read;


fn getLinesFromFile(file: string, ref lines: string[]) bool
{
	if (!exists(file)) {
		return false;
	}

	src := cast(string) read(file);

	foreach (line; splitLines(src)) {
		if (line.length > 0 && line[0] != '#') {
			lines ~= line;
		}
	}
	return true;
}
