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
	// Need either MSVC or clang.
	if (config.platform == Platform.MSVC) {
		drv.setTool(config.isHost, CLName, drv.fillInCommand(config, CLName));
		drv.setTool(config.isHost, LinkName, drv.fillInCommand(config, LinkName));
	} else {
		drv.setTool(config.isHost, ClangName, drv.fillInCommand(config, ClangName));
	}

	drv.setTool(config.isHost, NasmName, drv.fillInCommand(config, NasmName));
	drv.setTool(config.isHost, RdmdName, drv.fillInCommand(config, RdmdName));
}


/*
 *
 * Fill in configuration.
 *
 */

fn fillInConfigCommands(drv: Driver, config: Configuration)
{
	fillInLinkerAndCC(drv, config);

	config.rdmdCmd = config.getTool(RdmdName);
	config.nasmCmd = config.getTool(NasmName);
}

fn fillInLinkerAndCC(drv: Driver, config: Configuration)
{
	if (config.platform == Platform.MSVC) {
		fillInMSVC(drv, config);
		return;
	}

	// Try clang from the given tools.
	clang := config.getTool(ClangName);
	assert(clang !is null);

	config.ccCmd = clang;
	config.ccKind = CCKind.Clang;
	config.linkerCmd = clang;
	config.linkerKind = LinkerKind.Clang;
}

fn fillInMSVC(drv: Driver, config: Configuration)
{
	cl := config.getTool(CLName);
	link := config.getTool(LinkName);

	config.ccCmd = cl;
	config.ccKind = CCKind.CL;

	config.linkerCmd = link;
	config.linkerKind = LinkerKind.Link;
}
