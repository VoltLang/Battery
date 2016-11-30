// Copyright © 2016, Jakob Bornecrantz.  All rights reserved.
// See copyright notice in src/battery/license.volt (BOOST ver. 1.0).
/**
 * OS helpers.
 */
module battery.util.system;

import core.exception;
version (Windows) import core.windows;

fn processorCount() u32
{
	count: u32;
	version (Windows) {
		si: SYSTEM_INFO;
		GetSystemInfo(&si);
		count = si.dwNumberOfProcessors;
	} else {
		// TODO: http://stackoverflow.com/questions/150355/programmatically-find-the-number-of-cores-on-a-machine
		count = 9;
	}
	if (count == 0) {
		throw new Exception("processorCount failed to detect cpus.");
	}
	return count;
}
