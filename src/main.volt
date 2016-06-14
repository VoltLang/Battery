// Copyright © 2015-2016, Jakob Bornecrantz.  All rights reserved.
// See copyright notice in src/battery/license.volt (BOOST ver. 1.0).
module main;

import watt.io : writefln;

import battery.driver;
import battery.license;


int main(string[] args)
{
	drv := new DefaultDriver();
	drv.process(args);

	return 0;
}

void printLicense()
{
	foreach (l; licenseArray) {
		writefln(l);
	}
}
