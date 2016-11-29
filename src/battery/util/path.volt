// Copyright © 2016, Jakob Bornecrantz.  All rights reserved.
// See copyright notice in src/battery/license.volt (BOOST ver. 1.0).
/**
 * Path helpers.
 */
module battery.util.path;

import watt.text.string : replace;

fn cleanPath(s: string) string
{
	version (Windows) {
		return s.replace(":", "");
	} else {
		return s;
	}
}
