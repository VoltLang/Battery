// Copyright © 2015-2016, Jakob Bornecrantz.  All rights reserved.
// See copyright notice in src/battery/license.volt (BOOST ver. 1.0).
module main;

import watt.io : writefln;

import battery.defines;
import battery.license;
import battery.compile;
import battery.configuration;


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
	auto config = getHostConfig();
	auto v = config.volta;

	auto vrt = new Compile();
	vrt.library = true;
	vrt.derivedTarget = v.rtBin;
	vrt.srcRoot = v.rtDir;
	vrt.name = "vrt";
	vrt.libs = v.rtLibs;

	auto c = new Compile();
	c.deps = [vrt];
	c.name = "a.out";
	c.srcRoot = "test";
	c.src = ["test/test.volt"];
	c.derivedTarget = "a.out";

	auto ret = buildCmd(config, c);
	foreach (r; ret[1 .. $]) {
		writefln("%s", r);
	}
}

Configuration getHostConfig()
{
	auto volta = new Volta();
	volta.cmd = "volt";
	volta.rtBin = "%@execdir%/rt/libvrt-%@arch%-%@platform%.o";
	volta.rtDir = "%@execdir%/rt/src";
	volta.rtLibs = ["gc", "dl"];

	auto c = new Configuration();
	c.volta = volta;
	c.arch = Arch.X86_64;
	c.platform = Platform.Linux;

	return c;
}

void printLicense()
{
	foreach (l; licenseArray) {
		writefln(l);
	}
}
