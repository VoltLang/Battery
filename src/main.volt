// Copyright © 2015-2016, Jakob Bornecrantz.  All rights reserved.
// See copyright notice in src/battery/license.volt (BOOST ver. 1.0).
module main;

version (Windows) import core.c.windows.windows;

import io = watt.io;

import battery.driver;
import battery.license;


fn main(args: string[]) int
{
	version (Windows) {
		SetPriorityClass(GetCurrentProcess(), BELOW_NORMAL_PRIORITY_CLASS);
	}
	drv := new DefaultDriver();
	drv.process(args);

	return 0;
}

fn printLicense()
{
	foreach (l; licenseArray) {
		io.writefln(l);
	}
}
