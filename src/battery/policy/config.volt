// Copyright © 2016, Jakob Bornecrantz.  All rights reserved.
// See copyright notice in src/battery/license.volt (BOOST ver. 1.0).
/**
 * Logic for setting up configs.
 */
module battery.policy.config;

import watt.text.string : join;
import watt.text.format : format;
import watt.text.path : normalizePath;
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

		if (config.platform != Platform.MSVC) {
			drv.abort("can not cross compile on Windows");
		}

		// Volta needs the temp dir.
		copyIfNotSet("TEMP");

		// Only needed for RDMD if the installer wasn't used.
		copyIfNotSet("VCINSTALLDIR");
		copyIfNotSet("WindowsSdkDir");
		copyIfNotSet("WindowsSDKVersion");
		copyIfNotSet("UniversalCRTSdkDir");
		copyIfNotSet("UCRTVersion");

		// CL need these.
		copyIfNotSet("SYSTEMROOT");

		// Setup 
		doEnvMSVC(drv, config, outside);
	}
}

fn doEnvMSVC(drv: Driver, config: Configuration, outside: Environment)
{
	inc, lib: string[];

	getDirsForMSVC(drv, outside, out inc, out lib);

	// Set the built env vars.
	config.env.set("INCLUDE", join(inc, ";"));
	config.env.set("LIB", join(lib, ";"));
}

fn getDirsForMSVC(drv: Driver, outside: Environment, out inc: string[], out lib: string[])
{
	fn getOrWarn(name: string) string {
		value := outside.getOrNull(name);
		if (value.length == 0) {
			drv.info("error: need to set env var '%s'", name);
		}
		return value;
	}

	dirVC := getOrWarn("VCINSTALLDIR");
	dirUCRT := getOrWarn("UniversalCRTSdkDir");
	dirWinSDK := getOrWarn("WindowsSdkDir");
	numUCRT := getOrWarn("UCRTVersion");
	numWinSDK := getOrWarn("WindowsSDKVersion");

	if (dirVC.length == 0 || dirUCRT.length == 0 || dirWinSDK.length == 0 ||
	    numUCRT.length == 0 || numWinSDK.length == 0) {
		drv.abort("missing environmental variable");
	}

	inc = [
		normalizePath(format("%s/include", dirVC)),
		normalizePath(format("%s/include/%s/ucrt", dirUCRT, numUCRT)),
		normalizePath(format("%s/include/%s/shared", dirWinSDK, numWinSDK)),
		normalizePath(format("%s/include/%s/um", dirWinSDK, numWinSDK)),
		normalizePath(format("%s/include/%s/winrt", dirWinSDK, numWinSDK))
	];

	lib = [
		normalizePath(format("%s/lib/amd64", dirVC)),
		normalizePath(format("%s/lib/%s/ucrt/x64", dirUCRT, numUCRT)),
		normalizePath(format("%s/lib/%s/um/x64", dirWinSDK, numWinSDK))
	];
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
