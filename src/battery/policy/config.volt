// Copyright © 2016, Jakob Bornecrantz.  All rights reserved.
// See copyright notice in src/battery/license.volt (BOOST ver. 1.0).
/**
 * Logic for setting up configs.
 */
module battery.policy.config;

import watt.process : retrieveEnvironment, Environment, searchPath;
import battery.interfaces;
import battery.configuration;
import battery.policy.tools;


fn getBaseConfig(drv: Driver, arch: Arch, platform: Platform) Configuration
{
	c := new Configuration();
	c.env = new Environment();
	c.arch = arch;
	c.platform = platform;

	return c;
}

fn doConfig(drv: Driver, config: Configuration)
{
	doEnv(drv, config);

	// Need either MSVC or clang.
	if (config.platform == Platform.MSVC) {
		drv.setTool(config.isHost, CLName, drv.fillInCommand(config, CLName));
		drv.setTool(config.isHost, LinkName, drv.fillInCommand(config, LinkName));
	} else {
		drv.setTool(config.isHost, ClangName, drv.fillInCommand(config, ClangName));
	}

	drv.setTool(config.isHost, NasmName, drv.fillInCommand(config, NasmName));
	drv.setTool(config.isHost, RdmdName, drv.fillInCommand(config, RdmdName));
	tesla := drv.makeCommand(config, TeslaName, TeslaCommand, TeslaPrint);
	if (tesla !is null) {
		drv.setTool(config.isHost, TeslaName, tesla);
	}
}

fn doEnv(drv: Driver, config: Configuration)
{
	outside := retrieveEnvironment();

	fn copyIfNotSet(name: string) {

		if (config.env.isSet(name)) {
			return;
		}

		value := outside.getOrNull(name);
		if (value is null) {
			return;
		}

		config.env.set(name, value);
	}

	// Needed for all.
	copyIfNotSet("PATH");

	version (Windows) {
		// Volta needs the temp dir.
		copyIfNotSet("TEMP");

		// CL and Link needs these.
		copyIfNotSet("LIB");
		copyIfNotSet("LIBPATH");

		// CL need these.
		copyIfNotSet("INCLUDE");
		copyIfNotSet("SYSTEMROOT");

		// Only needed for RDMD if the installer wasn't used.
		copyIfNotSet("VCINSTALLDIR");
		copyIfNotSet("WindowsSdkDir");
		copyIfNotSet("UniversalCRTSdkDir");
		copyIfNotSet("UCRTVersion");
	}
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
