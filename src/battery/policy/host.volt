// Copyright © 2015-2016, Jakob Bornecrantz.  All rights reserved.
// See copyright notice in src/battery/license.volt (BOOST ver. 1.0).
module battery.policy.host;

import battery.configuration;
import battery.util.path : searchPath;
import battery.policy.volta : getVolta;


version (MSVC) {
	enum VoltaCommand = "volt.exe";
	enum HostLinkerCommand = "link.exe";
	enum HostLinkerFlag = "--link";
	enum HostPlatform = Platform.MSVC;
} else version (Linux) {
	enum VoltaCommand = "volt";
	enum HostLinkerCommand = "gcc";
	enum HostLinkerFlag = "--cc";
	enum HostPlatform = Platform.Linux;
} else version (OSX) {
	enum VoltaCommand = "volt";
	enum HostLinkerCommand = "clang";
	enum HostLinkerFlag = "--cc";
	enum HostPlatform = Platform.OSX;
} else {
	static assert(false, "native platform not supported");
}

version (X86_64) {
	enum Arch HostArch = Arch.X86_64;
} else version (X86) {
	enum Arch HostArch = Arch.X86;
} else {
	static assert(false, "native arch not supported");
}

Configuration getHostConfig(string path)
{
	volta := getVolta(path);
	linker := getHostLinker(path);

	c := new Configuration();
	c.path = path;
	c.volta = volta;
	c.linker = linker;
	c.arch = HostArch;
	c.platform = HostPlatform;

	return c;
}

Linker getHostLinker(string path)
{
	linker := new Linker();
	linker.cmd = searchPath(HostLinkerCommand, path);
	linker.flag = HostLinkerFlag;

	return linker;
}
