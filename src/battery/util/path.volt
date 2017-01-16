// Copyright © 2016, Jakob Bornecrantz.  All rights reserved.
// See copyright notice in src/battery/license.volt (BOOST ver. 1.0).
/**
 * Path helpers.
 */
module battery.util.path;

import watt.text.string : replace;
import watt.text.path : normalizePath, makePathAppendable;

fn cleanPath(s: string) string
{
	return normalizePath(makePathAppendable(s));
}
