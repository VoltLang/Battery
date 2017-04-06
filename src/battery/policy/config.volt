// Copyright © 2016, Jakob Bornecrantz.  All rights reserved.
// See copyright notice in src/battery/license.volt (BOOST ver. 1.0).
/**
 * Logic for setting up configs.
 */
module battery.policy.config;

import watt.io.file : isDir;
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
	outside := retrieveEnvironment();
	doEnv(drv, config, outside);

	drv.setTool(config.isHost, RdmdName, drv.fillInCommand(config, RdmdName));
	drv.setTool(config.isHost, NasmName, drv.fillInCommand(config, NasmName));

	final switch (config.platform) with (Platform) {
	case MSVC:
		if (config.isCross) {
			doToolChainCrossMSVC(drv, config, outside);
		} else {
			doToolChainNativeMSVC(drv, config, outside);
		}
		break;
	case Metal, Linux, OSX:
		doToolChainClang(drv, config, outside);
		break;
	}
}

fn doEnv(drv: Driver, config: Configuration, outside: Environment)
{
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

		// CL need these.
		copyIfNotSet("SYSTEMROOT");

		// Only needed for RDMD if the installer wasn't used.
		copyIfNotSet("VCINSTALLDIR");
		copyIfNotSet("WindowsSdkDir");
		copyIfNotSet("WindowsSDKVersion");
		copyIfNotSet("UniversalCRTSdkDir");
		copyIfNotSet("UCRTVersion");
	}
}


/*
 *
 * Clang based Toolchain.
 *
 */

fn doToolChainClang(drv: Driver, config: Configuration, outside: Environment)
{
	drv.setTool(config.isHost, ClangName, drv.fillInCommand(config, ClangName));
}


/*
 *
 * MSVC Toolchain.
 *
 */

struct VarsForMSVC
{
public:
	dirVC: string;
	dirUCRT: string;
	dirWinSDK: string;
	numUCRT: string;
	numWinSDK: string;

	/// Include directories, derived from the above fields.
	inc: string[];
	/// Library directories, derived from the above fields.
	lib: string[];
	/// Extra path, for binaries.
	path: string[];


public:
	fn addIncIfIsDir(dir: string) {
		dir = normalizePath(dir);
		if (isDir(dir)) {
			inc ~= dir;
		}
	}

	fn addLibIfIsDir(dir: string) {
		dir = normalizePath(dir);
		if (isDir(dir)) {
			lib ~= dir;
		}
	}
}

fn doToolChainNativeMSVC(drv: Driver, config: Configuration, outside: Environment)
{
	drv.setTool(config.isHost, ClangName, drv.fillInCommand(config, ClangName));
	drv.setTool(config.isHost, LinkName, drv.fillInCommand(config, LinkName));

	vars: VarsForMSVC;
	getDirsFromEnv(drv, outside, ref vars);
	fillInListsForMSVC(ref vars);

	// Set the built env vars.
	config.env.set("INCLUDE", join(vars.inc, ";"));
	config.env.set("LIB", join(vars.lib, ";"));


	link := drv.getTool(false, LinkName);
	link.args ~= [
		"/nologo",
		"/defaultlib:libcmt",
		"/defaultlib:oldnames",
		"legacy_stdio_definitions.lib",
	];
}

fn doToolChainCrossMSVC(drv: Driver, config: Configuration, outside: Environment)
{
	assert(!config.isHost);

	drv.setTool(false, ClangName, drv.fillInCommand(config, ClangName));
	drv.setTool(false, LinkName, drv.fillInCommand(config, LinkName));

	vars: VarsForMSVC;
	getDirsFromEnv(drv, outside, ref vars);
	fillInListsForMSVC(ref vars);

	clang := drv.getTool(false, ClangName);
	foreach (i; vars.inc) {
		clang.args ~= "-I" ~ i;
	}

	link := drv.getTool(false, LinkName);
	link.args ~= [
		"/nologo",
		"/defaultlib:libcmt",
		"/defaultlib:oldnames",
		"legacy_stdio_definitions.lib",
	];

	foreach (l; vars.lib) {
		link.args ~= format("/LIBPATH:%s", l);
	}
}

fn getDirsFromEnv(drv: Driver, env: Environment, ref vars: VarsForMSVC)
{
	fn getOrWarn(name: string) string {
		value := env.getOrNull(name);
		if (value.length == 0) {
			drv.info("error: need to set env var '%s'", name);
		}
		return value;
	}

	vars.dirVC = getOrWarn("VCINSTALLDIR");
	vars.dirUCRT = getOrWarn("UniversalCRTSdkDir");
	vars.dirWinSDK = getOrWarn("WindowsSdkDir");
	vars.numUCRT = getOrWarn("UCRTVersion");
	vars.numWinSDK = getOrWarn("WindowsSDKVersion");

	if (vars.dirVC.length == 0 || vars.dirUCRT.length == 0 ||
	    vars.dirWinSDK.length == 0 || vars.numUCRT.length == 0 ||
	    vars.numWinSDK.length == 0) {
		drv.abort("missing environmental variable");
	}
}

fn fillInListsForMSVC(ref vars: VarsForMSVC)
{
	fn tPath(dir: string) {
		dir = normalizePath(dir);
		if (isDir(dir)) {
			vars.path ~= dir;
		}
	}

	fn tInc(dir: string) {
		dir = normalizePath(dir);
		if (isDir(dir)) {
			vars.inc ~= dir;
		}
	}

	fn tLib(dir: string) {
		dir = normalizePath(dir);
		if (isDir(dir)) {
			vars.lib ~= dir;
		}
	}

	tPath(format("%s/bin/x64", vars.dirWinSDK));
	tPath(format("%s/bin/x86", vars.dirWinSDK));
	tPath(format("%s/VCPackages", vars.dirVC));
	tPath(format("%s/BIN/amd64", vars.dirVC));

	tInc(format("%s/include", vars.dirVC));
	tInc(format("%s/include/%s/ucrt", vars.dirUCRT, vars.numUCRT));
	tInc(format("%s/include/%s/shared", vars.dirWinSDK, vars.numWinSDK));
	tInc(format("%s/include/%s/um", vars.dirWinSDK, vars.numWinSDK));
	tInc(format("%s/include/%s/winrt", vars.dirWinSDK, vars.numWinSDK));

	tLib(format("%s/lib/amd64", vars.dirVC));
	tLib(format("%s/lib/%s/ucrt/x64", vars.dirUCRT, vars.numUCRT));
	tLib(format("%s/lib/%s/um/x64", vars.dirWinSDK, vars.numWinSDK));
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
	final switch (config.platform) with (Platform) {
	case MSVC:
		if (config.isCross) {
			fillInClang(drv, config);
			fillInLink(drv, config);
		} else {
			fillInClang(drv, config);
			fillInLink(drv, config);
		}
		break;
	case Metal, Linux, OSX:
		fillInClang(drv, config);
		break;
	}
}

fn fillInClang(drv: Driver, config: Configuration)
{
	// Try clang from the given tools.
	clang := config.getTool(ClangName);

	config.ccCmd = clang;
	config.ccKind = CCKind.Clang;
	config.linkerCmd = clang;
	config.linkerKind = LinkerKind.Clang;
}

fn fillInLink(drv: Driver, config: Configuration)
{
	link := config.getTool(LinkName);

	config.linkerCmd = link;
	config.linkerKind = LinkerKind.Link;
}

fn fillInCL(drv: Driver, config: Configuration)
{
	cl := config.getTool(CLName);
	config.ccCmd = cl;
	config.ccKind = CCKind.CL;
}
