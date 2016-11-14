// Copyright © 2016, Jakob Bornecrantz.  All rights reserved.
// See copyright notice in src/battery/license.volt (BOOST ver. 1.0).
/**
 * Logic for setting up configs.
 */
module battery.policy.config;

import watt.process : retrieveEnvironment, Environment, searchPath;
import battery.interfaces;
import battery.configuration;
import battery.policy.programs;


fn getBaseConfig(drv: Driver, arch: Arch, platform: Platform) Configuration
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

		// Only needed for RDMD if the installer wasn't used.
		env.set("VCINSTALLDIR", outside.getOrNull("VCINSTALLDIR"));
		env.set("WindowsSdkDir", outside.getOrNull("WindowsSdkDir"));
		env.set("UniversalCRTSdkDir", outside.getOrNull("UniversalCRTSdkDir"));
		env.set("UCRTVersion", outside.getOrNull("UCRTVersion"));
	}

	c := new Configuration();
	c.env = env;
	c.arch = arch;
	c.platform = platform;

	return c;
}

fn doConfig(drv: Driver, config: Configuration, host: bool)
{
	clStr := host ? "host-cl" : "cl";
	linkStr := host ? "host-link" : "link";
	rdmdStr := host ? "host-rdmd" : "rdmd";
	nasmStr := host ? "host-nasm" : "nasm";
	clangStr := host ? "host-clang" : "clang";

	// Need either MSVC or clang.
	if (config.platform == Platform.MSVC) {
		drv.setTool(clStr, drv.fillInCommand(config, clStr));
		drv.setTool(linkStr, drv.fillInCommand(config, linkStr));
	} else {
		drv.setTool(clangStr, drv.fillInCommand(config, clangStr));
	}

	drv.setTool(nasmStr, drv.fillInCommand(config, nasmStr));
	drv.setTool(rdmdStr, drv.fillInCommand(config, rdmdStr));
}

/*
 *
 * Fill in configuration.
 *
 */

fn fillInConfigCommands(drv: Driver, config: Configuration, host: bool)
{
	fillInLinkerAndCC(drv, config, host);

	rdmdStr := host ? "host-rdmd" : "rdmd";
	nasmStr := host ? "host-nasm" : "nasm";

	config.rdmdCmd = drv.getTool(rdmdStr);
	config.nasmCmd = drv.getTool(nasmStr);
}

fn fillInLinkerAndCC(drv: Driver, config: Configuration, host: bool)
{
	if (config.platform == Platform.MSVC) {
		fillInMSVC(drv, config, host);
		return;
	}

	// Try clang from the given tools.
	clangStr := host ? "host-clang" : "clang";
	clang := drv.getTool(clangStr);
	assert(clang !is null);

	config.ccCmd = clang;
	config.ccKind = CCKind.Clang;
	config.linkerCmd = clang;
	config.linkerKind = LinkerKind.Clang;
}

fn fillInMSVC(drv: Driver, config: Configuration, host: bool)
{
	clStr := host ? "host-cl" : "cl";
	linkStr := host ? "host-link" : "link";

	cl := drv.getTool(clStr);
	link := drv.getTool(linkStr);

	config.ccCmd = cl;
	config.ccKind = CCKind.CL;

	config.linkerCmd = link;
	config.linkerKind = LinkerKind.Link;
}
