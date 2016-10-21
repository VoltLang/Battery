// Copyright © 2015-2016, Jakob Bornecrantz.  All rights reserved.
// See copyright notice in src/battery/license.volt (BOOST ver. 1.0).
module battery.policy.host;

import watt.process : retrieveEnvironment, Environment, searchPath;
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

fn getBaseHostConfig(drv: Driver) Configuration
{
	outside := retrieveEnvironment();
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

	return c;
}

fn doHostConfig(drv: Driver, host: Configuration)
{
	// Need either MSVC or clang.
	if (host.platform == Platform.MSVC) {
		drv.setTool("cl", drv.fillInCommand(host, "cl"));
		drv.setTool("link", drv.fillInCommand(host, "link"));
	} else {
		drv.setTool("clang", drv.fillInCommand(host, "clang"));
	}

	drv.setTool("nasm", drv.fillInCommand(host, "nasm"));
	drv.setTool("rdmd", drv.fillInCommand(host, "rdmd"));
}

fn fillInHostConfig(drv: Driver, host: Configuration)
{
	drv.setupHostLinkerAndCC(host);

	host.rdmdCmd = drv.getTool("rdmd");
	host.nasmCmd = drv.getTool("nasm");
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

	// Try clang from the given tools.
	clang := drv.getTool("clang");
	assert(clang !is null);

	host.ccCmd = clang;
	host.ccKind = CCKind.Clang;
	host.linkerCmd = clang;
	host.linkerKind = LinkerKind.Clang;
}

fn setupMSVC(drv: Driver, host: Configuration)
{
	cl := drv.getTool("cl");
	link := drv.getTool("link");

	host.ccCmd = cl;
	host.ccKind = CCKind.CL;

	host.linkerCmd = link;
	host.linkerKind = LinkerKind.Link;
}
