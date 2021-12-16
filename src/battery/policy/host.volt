// Copyright 2015-2018, Jakob Bornecrantz.
// SPDX-License-Identifier: BSL-1.0
module battery.policy.host;

import watt.process : retrieveEnvironment, Environment, searchPath;
import battery.interfaces;
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

version (ARMHF) {
	enum Arch HostArch = Arch.ARMHF;
} else version (AArch64) {
	enum Arch HostArch = Arch.AArch64;
} else version (X86_64) {
	enum Arch HostArch = Arch.X86_64;
} else version (X86) {
	enum Arch HostArch = Arch.X86;
} else {
	static assert(false, "native arch not supported");
}

fn getProjectHostConfig(drv: Driver) Configuration
{
	c := getProjectConfig(drv, HostArch, HostPlatform);
	c.kind = ConfigKind.Host;
	return c;
}
