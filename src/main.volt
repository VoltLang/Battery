// Copyright © 2015-2016, Jakob Bornecrantz.  All rights reserved.
// See copyright notice in src/battery/license.volt (BOOST ver. 1.0).
module main;

import watt.io : writefln;

import battery.defines;
import battery.license;
import battery.compile;


int main(string[] args)
{
	foreach (arg; args[1 .. $]) {
		if (arg == "--license") {
			printLicense();
			return 0;
		}
	}

	doBuild();

	return 0;
}


void doBuild()
{
	auto t = new Target();
	t.arch = Arch.X86_64;
	t.platform = Platform.Linux;

	auto v = new Volta();
	v.cmd = "volt";

	auto vrt = new Compile();
	vrt.library = true;
	vrt.derivedTarget = "%@execdir%/rt/libvrt-%@arch%-%@platform%.o";
	vrt.name = "vrt";
	vrt.srcRoot = "%@execdir%/rt/src";
	vrt.libs = ["gc", "rt", "dl"];

	auto c = new Compile();
	c.deps = [vrt];
	c.name = "a.out";
	c.srcRoot = "test";
	c.src = ["test/test.volt"];
	c.derivedTarget = "a.out";


	auto ret = buildCmd(v, t, c);
	foreach (r; ret[1 .. $]) {
		writefln("%s", r);
	}
}

void printLicense()
{
	foreach (l; licenseArray) {
		writefln(l);
	}
}
