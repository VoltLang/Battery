// Copyright © 2015-2016, Jakob Bornecrantz.  All rights reserved.
// See copyright notice in src/battery/license.volt (BOOST ver. 1.0).
module battery.policy.volta;

import battery.configuration;
import battery.util.path : searchPath;


version (MSVC) {
	enum VoltaCommand = "volt.exe";
} else version (Linux) {
	enum VoltaCommand = "volt";
} else version (OSX) {
	enum VoltaCommand = "volt";
} else {
	static assert(false, "native platform not supported");
}

Volta getVolta(string path)
{
	auto volta = new Volta();
	volta.cmd = searchPath(VoltaCommand, path);
	volta.rtBin = "%@execdir%/rt/libvrt-%@arch%-%@platform%.o";
	volta.rtDir = "%@execdir%/rt/src";
	volta.rtLibs[Platform.Linux] = ["gc", "dl", "rt"];
	volta.rtLibs[Platform.MSVC] = ["advapi32.lib"];
	volta.rtLibs[Platform.OSX] = ["gc"];

	return volta;
}
