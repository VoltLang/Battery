// Copyright © 2017-2018, Bernard Helyer.  All rights reserved.
// Copyright © 2017-2018, Jakob Bornecrantz.  All rights reserved.
// See copyright notice in src/battery/license.volt (BOOST ver. 1.0).
/**
 * Lower priority setter function.
 */
module battery.util.priority;

version (Windows) import core.c.windows.windows;


/*!
 * Only works on windows currently, just so battery doesn't nuke your computer.
 */
fn setLowPriority()
{
	version (Windows) {
		SetPriorityClass(GetCurrentProcess(), BELOW_NORMAL_PRIORITY_CLASS);
	}
}
