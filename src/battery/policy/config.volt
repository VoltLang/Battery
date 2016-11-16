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
	clStr := "cl";
	linkStr := "link";
	rdmdStr := "rdmd";
	nasmStr := "nasm";
	clangStr := "clang";

	// Need either MSVC or clang.
	if (config.platform == Platform.MSVC) {
		drv.setTool(host, clStr, drv.fillInCommand(config, host, clStr));
		drv.setTool(host, linkStr, drv.fillInCommand(config, host, linkStr));
	} else {
		drv.setTool(host, clangStr, drv.fillInCommand(config, host, clangStr));
	}

	drv.setTool(host, nasmStr, drv.fillInCommand(config, host, nasmStr));
	drv.setTool(host, rdmdStr, drv.fillInCommand(config, host, rdmdStr));
}

/*
 *
 * Fill in configuration.
 *
 */

fn fillInConfigCommands(drv: Driver, config: Configuration, host: bool)
{
	fillInLinkerAndCC(drv, config, host);

	rdmdStr := "rdmd";
	nasmStr := "nasm";

	config.rdmdCmd = drv.getTool(host, rdmdStr);
	config.nasmCmd = drv.getTool(host, nasmStr);
}

fn fillInLinkerAndCC(drv: Driver, config: Configuration, host: bool)
{
	if (config.platform == Platform.MSVC) {
		fillInMSVC(drv, config, host);
		return;
	}

	// Try clang from the given tools.
	clangStr := "clang";
	clang := drv.getTool(host, clangStr);
	assert(clang !is null);

	config.ccCmd = clang;
	config.ccKind = CCKind.Clang;
	config.linkerCmd = clang;
	config.linkerKind = LinkerKind.Clang;
}

fn fillInMSVC(drv: Driver, config: Configuration, host: bool)
{
	clStr := "cl";
	linkStr := "link";

	cl := drv.getTool(host, clStr);
	link := drv.getTool(host, linkStr);

	config.ccCmd = cl;
	config.ccKind = CCKind.CL;

	config.linkerCmd = link;
	config.linkerKind = LinkerKind.Link;
}
