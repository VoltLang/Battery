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

fn doConfig(drv: Driver, config: Configuration)
{
	clStr := "cl";
	linkStr := "link";
	rdmdStr := "rdmd";
	nasmStr := "nasm";
	clangStr := "clang";

	// Need either MSVC or clang.
	if (config.platform == Platform.MSVC) {
		drv.setTool(config.isHost, clStr, drv.fillInCommand(config, clStr));
		drv.setTool(config.isHost, linkStr, drv.fillInCommand(config, linkStr));
	} else {
		drv.setTool(config.isHost, clangStr, drv.fillInCommand(config, clangStr));
	}

	drv.setTool(config.isHost, nasmStr, drv.fillInCommand(config, nasmStr));
	drv.setTool(config.isHost, rdmdStr, drv.fillInCommand(config, rdmdStr));
}

/*
 *
 * Fill in configuration.
 *
 */

fn fillInConfigCommands(drv: Driver, config: Configuration)
{
	fillInLinkerAndCC(drv, config);

	rdmdStr := "rdmd";
	nasmStr := "nasm";

	config.rdmdCmd = config.getTool(rdmdStr);
	config.nasmCmd = config.getTool(nasmStr);
}

fn fillInLinkerAndCC(drv: Driver, config: Configuration)
{
	if (config.platform == Platform.MSVC) {
		fillInMSVC(drv, config);
		return;
	}

	// Try clang from the given tools.
	clangStr := "clang";
	clang := config.getTool(clangStr);
	assert(clang !is null);

	config.ccCmd = clang;
	config.ccKind = CCKind.Clang;
	config.linkerCmd = clang;
	config.linkerKind = LinkerKind.Clang;
}

fn fillInMSVC(drv: Driver, config: Configuration)
{
	clStr := "cl";
	linkStr := "link";

	cl := config.getTool(clStr);
	link := config.getTool(linkStr);

	config.ccCmd = cl;
	config.ccKind = CCKind.CL;

	config.linkerCmd = link;
	config.linkerKind = LinkerKind.Link;
}
