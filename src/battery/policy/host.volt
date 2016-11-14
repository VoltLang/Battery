// Copyright © 2015-2016, Jakob Bornecrantz.  All rights reserved.
// See copyright notice in src/battery/license.volt (BOOST ver. 1.0).
module battery.policy.host;

import watt.process : retrieveEnvironment, Environment, searchPath;
import battery.interfaces;
import battery.configuration;
import battery.policy.config;


version (MSVC) {
	enum HostPlatform = Platform.MSVC;
} else version (Linux) {
	enum HostPlatform = Platform.Linux;
} else version (OSX) {
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

fn getBaseHostConfig(drv: Driver) Configuration
{
	return getBaseConfig(drv, HostArch, HostPlatform);
}
