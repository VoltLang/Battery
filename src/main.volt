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
	auto vrt = getRtCompile(config);

	auto c = new Compile();
	c.deps = [vrt];
	c.name = "a.out";
	c.srcRoot = "src";
	c.src = ["src/main.volt"];
	c.derivedTarget = "a.out";

	auto ret = buildCmd(config, c);
	foreach (r; ret[0 .. $]) {
		writefln("%s", r);
	}
}

Volta getVolta()
{
	auto volta = new Volta();
	volta.cmd = "volt";
	volta.rtBin = "%@execdir%/rt/libvrt-%@arch%-%@platform%.o";
	volta.rtDir = "%@execdir%/rt/src";
	volta.rtLibs[Platform.Linux] = ["gc", "dl", "rt"];
	volta.rtLibs[Platform.MSVC] = ["advapi32.lib"];
	volta.rtLibs[Platform.OSX] = ["gc"];

	return volta;
}

Compile getRtCompile(Configuration config)
{
	auto vrt = new Compile();
	vrt.library = true;
	vrt.derivedTarget = config.volta.rtBin;
	vrt.srcRoot = config.volta.rtDir;
	vrt.libs = config.volta.rtLibs[config.platform];
	vrt.name = "vrt";

	return vrt;
}

Configuration getHostConfig()
{
	auto volta = getVolta();
	auto c = new Configuration(volta);


	version (X86_64) {
		c.arch = Arch.X86_64;
	} else version (X86) {
		c.arch = Arch.X86;
	} else {
		static assert(false, "native arch not supported");
	}

	version (MSVC) {
		c.platform = Platform.MSVC;
	} else version (Linux) {
		c.platform = Platform.Linux;
	} else version (OSX) {
		c.platform = Platform.OSX;
	} else {
		static assert(false, "native platform not supported");
	}

	return c;
}

void printLicense()
{
	foreach (l; licenseArray) {
		writefln(l);
	}
}
