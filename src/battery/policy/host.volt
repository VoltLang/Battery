// Copyright © 2015-2016, Jakob Bornecrantz.  All rights reserved.
// See copyright notice in src/battery/license.volt (BOOST ver. 1.0).
module battery.policy.host;

import watt.process : retriveEnvironment, Environment, searchPath;
import battery.interfaces;
import battery.configuration;
import battery.policy.programs;

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

fn getHostConfig(drv: Driver) Configuration
{
	outside := retriveEnvironment();
	path := outside.getOrNull("PATH");

	env := new Environment();
	// Needed for all.
	env.set("PATH", path);

	version (Windows) {
		// Volta needs the temp dir.
		env.set("TEMP", outside.getOrNull("TEMP"));

		// CL and Link needs these.
		env.set("LIB", outside.getOrNull("LIB"));
		env.set("LIBPATH", outside.getOrNull("LIBPATH"));

		// CL need these.
		env.set("INCLUDE", outside.getOrNull("INCLUDE"));
		env.set("SYSTEMROOT", outside.getOrNull("SYSTEMROOT"));

		// Only needed for RDMD if it isn't installed properly.
		//env.set("VCINSTALLDIR", outside.getOrNull("VCINSTALLDIR"));
		//env.set("WindowsSdkDir", outside.getOrNull("WindowsSdkDir"));
		//env.set("UniversalCRTSdkDir", outside.getOrNull("UniversalCRTSdkDir"));
		//env.set("UCRTVersion", outside.getOrNull("UCRTVersion"));
	}

	c := new Configuration();
	c.env = env;
	c.arch = HostArch;
	c.platform = HostPlatform;
	drv.setupHostRdmd(c);
	drv.setupHostLinkerAndCC(c);
	drv.setupHostNasm(c);

	return c;
}


/*
 *
 * C compiler and linker functions.
 *
 */

fn setupHostLinkerAndCC(drv: Driver, host: Configuration)
{
	if (host.platform == Platform.MSVC) {
		setupMSVC(drv, host);
		return;
	}

	// Try clang first.
	clang := getClang(drv, host);
	if (clang !is null) {
		host.ccCmd = clang;
		host.ccKind = CCKind.Clang;
		host.linkerCmd = clang;
		host.linkerKind = LinkerKind.Clang;
		return;
	}

	// TODO: Maybe try GCC
	drv.abort("Can not find clang.");
}

fn setupHostNasm(drv: Driver, host: Configuration)
{
	host.nasmCmd = getNasm(drv, host);
}

fn setupHostRdmd(drv: Driver, host: Configuration)
{
	host.rdmdCmd = getRdmd(drv, host);
}
