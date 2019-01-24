// Copyright 2016-2018, Jakob Bornecrantz.
// SPDX-License-Identifier: BSL-1.0
/*!
 * Logic for setting up configs.
 */
module battery.policy.config;

import watt.io.file : isDir;
import watt.conv : toLower;
import watt.text.string : join, split;
import watt.text.format : format;
import watt.text.path : normalisePath;
import watt.process : retrieveEnvironment, Environment;
import battery.commonInterfaces;
import battery.configuration;
import battery.policy.tools;
import battery.util.path : searchPath;

import llvm = battery.detect.llvm;
import gdc = battery.detect.gdc;
import rdmd = battery.detect.rdmd;
import nasm = battery.detect.nasm;
import msvc = battery.detect.msvc;


fn getProjectConfig(drv: Driver, arch: Arch, platform: Platform) Configuration
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

	switch (config.kind) with (ConfigKind) {
	case Bootstrap:
		// We need llvm-config to build volted.
		doToolChainLLVM(drv, config, UseAsLinker.NO);

		// Do a bit of logging.
		drv.info("Various tools needed by bootstrapping.");

		// Get GDC if we are bootstrapping.
		if (doGDC(drv, config)) {
			return;
		}

		// Fallback to RDMD.
		if (doRDMD(drv, config)) {
			return;
		}
		return;
	default:
	}

	final switch (config.platform) with (Platform) {
	case MSVC:
		// Always setup a basic LLVM toolchain.
		doToolChainLLVM(drv, config, UseAsLinker.NO);

		// Overwrite the LLVM toolchain a tiny bit.
		if (config.isCross || config.isLTO) {
			doToolChainCrossMSVC(drv, config, outside);
		} else {
			doToolChainNativeMSVC(drv, config, outside);
		}
		break;
	case Metal, Linux, OSX:
		// Always setup a basic LLVM toolchain.
		doToolChainLLVM(drv, config, UseAsLinker.YES);
		break;
	}

	// Do a bit of logging.
	drv.info("Various tools needed by compile.");

	// Make it possible for the user to supply the volta.exe
	drvVolta := drv.getCmd(config.isBootstrap, "volta");
	if (drvVolta !is null) {
		config.addTool("volta", drvVolta.cmd, drvVolta.args);
		drv.infoCmd(config, drvVolta, "args");
	}

	// NASM is needed for RT.
	doNASM(drv, config);
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

fn fillInNeeded(ref need: llvm.Needed, config: Configuration)
{
	// For Windows llvm-config is not needed.
	version (!Windows) {
		need.config = true;
	}

	// Bootstrap does not require anything more.
	if (config.isBootstrap) {
		return;
	}

	// Need clang for the rest.
	need.clang = true;

	// Platform specific.
	final switch (config.platform) with (Platform) {
	case MSVC:
		need.link = config.isLTO || config.isCross;
		need.ar = config.isLTO;
		break;
	case Metal, Linux:
		need.ld = config.isLTO;
		need.ar = config.isLTO;
		break;
	case OSX:
		need.ar = config.isLTO;
		break;
	}
}

fn hasNeeded(ref res: llvm.Result, ref need: llvm.Needed) bool
{
	if (need.config && (res.configCmd is null)) return false;
	if (need.clang && (res.clangCmd is null)) return false;
	if (need.ar && (res.arCmd is null)) return false;
	if (need.link && (res.linkCmd is null)) return false;
	if (need.ld && (res.ldCmd is null)) return false;
	return true;
}

enum UseAsLinker
{
	NO,
	YES,
}

fn doToolChainLLVM(drv: Driver, config: Configuration, useLinker: UseAsLinker)
{
	fromArgs: llvm.FromArgs;
	results: llvm.Result[];
	result: llvm.Result;
	need: llvm.Needed;
	confPaths := [config.llvmConf];
	path := config.env.getOrNull("PATH");

	need.fillInNeeded(config);
	fillIfFound(drv, config, LLVMConfigName, out fromArgs.configCmd, out fromArgs.configArgs);
	fillIfFound(drv, config, LLVMArName, out fromArgs.arCmd, out fromArgs.arArgs);
	fillIfFound(drv, config, ClangName, out fromArgs.clangCmd, out fromArgs.clangArgs);
	fillIfFound(drv, config, LDLLDName, out fromArgs.ldCmd, out fromArgs.ldArgs);
	fillIfFound(drv, config, LLDLinkName, out fromArgs.linkCmd, out fromArgs.linkArgs);

	llvm.detectFrom(path, confPaths, out results);
	if (llvm.detectFromArgs(ref fromArgs, out result)) {
		results = result ~ results;
	}

	found: bool;
	foreach (ref res; results) {
		if (!res.hasNeeded(ref need)) {
			continue;
		}

		llvm.addArgs(ref res, config.arch, config.platform, out result);
		found = true;
		break;
	}

	if (!found) {
		drv.abort("No valid LLVM Toolchains found!");
	}

	configCommand: Command;
	arCommand: Command;
	ldCommand: Command;
	linkCommand: Command;
	clangCommand: Command;

	if (result.configCmd !is null && need.config) {
		configCommand = config.addTool(LLVMConfigName, result.configCmd, result.configArgs);
	}
	if (result.arCmd !is null && need.ar) {
		arCommand = config.addTool(LLVMArName, result.arCmd, result.arArgs);
	}
	if (result.ldCmd !is null && need.ld) {
		ldCommand = config.addTool(LDLLDName, result.ldCmd, result.ldArgs);
	}
	if (result.linkCmd !is null && need.link) {
		linkCommand = config.addTool(LLDLinkName, result.linkCmd, result.linkArgs);
	}

	// If needed setup the linker command.
	linker: Command;
	if (useLinker) {
		linker = drv.getCmd(config.isBootstrap, LinkerName);

		// If linker was not given use clang as the linker.
		// Always add it to the config.
		if (linker is null) {
			linker = config.addTool(LinkerName, result.clangCmd, result.clangArgs);
		} else {
			linker = config.addTool(LinkerName, linker.cmd, linker.args);
		}
	}

	if (!config.isBootstrap) {
		// A tiny bit of sanity checking.
		assert(result.clangCmd !is null);

		// Setup clang and cc tools.
		clang := config.addTool(ClangName, result.clangCmd, result.clangArgs);
		cc := config.addTool(CCName, result.clangCmd, result.clangArgs);

		// Add any extra arguments.
		if (config.isRelease) {
			clang.args ~= "-O3";
			cc.args ~= "-O3";
		} else if (config.platform == Platform.MSVC) { // Debug && MSVC.
			clang.args ~= ["-g", "-gcodeview"];
			cc.args ~= ["-g", "-gcodeview"];
		} else {
			clang.args ~= "-g";
			cc.args ~= "-g";
		}

		if (config.isLTO) {
			clang.args ~= "-flto=thin";
			cc.args ~= "-flto=thin";
			if (linker !is null) {
				linker.args ~= ["-flto=thin", "-fuse-ld=lld"];
			}
		}
	}

	config.llvmVersion = result.ver;

	drv.info("Using LLVM-%s toolchain from %s.", result.ver, result.from);
	if (configCommand !is null) drv.infoCmd(config, configCommand, result.from);
	if (clangCommand  !is null) drv.infoCmd(config, clangCommand,  result.from);
	if (arCommand     !is null) drv.infoCmd(config, arCommand,     result.from);
	if (ldCommand     !is null) drv.infoCmd(config, ldCommand,     result.from);
	if (linkCommand   !is null) drv.infoCmd(config, linkCommand,   result.from);
}


/*
 *
 * MSVC Toolchain.
 *
 */

struct VarsForMSVC
{
public:
	//! Old INCLUDE env variable, if found.
	oldInc: string;
	//! Old LIB env variable, if found.
	oldLib: string;
	//! Old PATH env variable, if found.
	oldPath: string;

	//! Best guess which MSVC thing we are using.
	msvcVer: msvc.VisualStudioVersion;

	//! Install directory for compiler and linker, from either
	//! @p VCTOOLSINSTALLDIR or @p VCINSTALLDIR env.
	dirVCInstall: string;

	dirUCRT: string;
	dirWinSDK: string;
	numUCRT: string;
	numWinSDK: string;

	//! Include directories, derived from the above fields.
	inc: string[];
	//! Library directories, derived from the above fields.
	lib: string[];
	//! Extra path, for binaries.
	path: string[];


public:
	fn tPath(dir: string) {
		dir = normalisePath(dir);
		if (isDir(dir)) {
			path ~= dir;
		}
	}

	fn tInc(dir: string) {
		dir = normalisePath(dir);
		if (isDir(dir)) {
			inc ~= dir;
		}
	}

	fn tLib(dir: string) {
		dir = normalisePath(dir);
		if (isDir(dir)) {
			lib ~= dir;
		}
	}
}

fn doToolChainNativeMSVC(drv: Driver, config: Configuration, outside: Environment)
{
	fn overideIfNotSet(name: string, value: string) {
		if (config.env.isSet(name)) {
			return;
		}

		config.env.set(name, value);
	}

	lib, inc, path: string;
	vars: VarsForMSVC;
	vars.getDirsFromRegistry(drv, outside);
	vars.fillInListsForMSVC();
	vars.genAndCheckEnv(drv, out inc, out lib, out path);

	config.env.set("INCLUDE", inc);
	config.env.set("LIB", lib);
	config.env.set("PATH", path);

	overideIfNotSet("UniversalCRTSdkDir", vars.dirUCRT);
	overideIfNotSet("WindowsSdkDir", vars.dirWinSDK);
	overideIfNotSet("UCRTVersion", vars.numUCRT);
	overideIfNotSet("WindowsSDKVersion", vars.numWinSDK);

	// First see if the linker is specified.
	linker := drv.getCmd(config.isBootstrap, LinkerName);
	linkerFromArg := true;
	linkerFromLLVM := false;

	// If it was not specified try getting 'link.exe' from the path.
	if (linker is null) {
		linker = config.makeCommandFromPath(LinkCommand, LinkName);
		linkerFromArg = false;
	}

	// If it was not specified or found get 'lld-link' from the LLVM toolchain.
	if (linker is null) {
		linker = config.getTool(LLDLinkName);
		linkerFromLLVM = true;
	}

	// Abort if we don't have a linker.
	if (linker is null) {
		drv.abort("Could not find a valid system linker!\n\tNeed either lld-link.exe or link.exe command.");
	}

	// Always add it to the config.
	assert(linker !is null);
	linker = config.addTool(LinkerName, linker.cmd, linker.args);

	// Always add the common arguments to the linker.
	addCommonLinkerArgsMSVC(config, linker);

	verStr := msvc.visualStudioVersionToString(vars.msvcVer);
	drv.info("Using Visual Studio Build Tools %s.", verStr);
	if (linkerFromLLVM) {
		drv.info("\tcmd linker: Linking with lld-link.exe from LLVM toolchain.");
	} else {
		drv.infoCmd(config, linker, linkerFromArg ? "args" : "path");
	}

	cl := config.makeCommandFromPath(CLCommand, CLName);
	if (cl !is null) {
		/* We don't use this in the build, but it does get used to test
		 * the ABI on Windows; so we don't error if it's missing, but
		 * we do add it if we see it.
		 */
		config.addTool(CLName, cl.cmd, cl.args);
	}
}

fn doToolChainCrossMSVC(drv: Driver, config: Configuration, outside: Environment)
{
	assert(!config.isBootstrap);

	// First see if the linker is specified.
	linker := drv.getCmd(config.isBootstrap, LinkerName);
	linkerFromArg := true;

	// If it was not specified get 'lld-link' from the LLVM toolchain.
	if (linker is null) {
		linker = config.getTool(LLDLinkName);
		linkerFromArg = false;
	}

	// Always add it to the config.
	assert(linker !is null);
	linker = config.addTool(LinkerName, linker.cmd, linker.args);

	// Always add the common arguments to the linker.
	addCommonLinkerArgsMSVC(config, linker);

	// Get the CC setup by the llvm toolchain.
	cc := config.getTool(CCName);
	assert(cc !is null);

	vars: VarsForMSVC;
	vars.getDirsFromEnv(drv, outside);
	vars.fillInListsForMSVC();

	foreach (i; vars.inc) {
		cc.args ~= "-I" ~ i;
	}

	foreach (l; vars.lib) {
		linker.args ~= format("/LIBPATH:%s", l);
	}

	verStr := msvc.visualStudioVersionToString(vars.msvcVer);
	drv.info("Using MSVC %s from the enviroment.", verStr);
	if (linkerFromArg) {
		drv.infoCmd(config, linker, linkerFromArg ? "args" : "path");
	}
}

fn getDirsFromRegistry(ref vars: VarsForMSVC, drv: Driver, env: Environment)
{
	vsInstalls: msvc.Result[];
	fromEnv: msvc.FromEnv;
	fromEnv.vcInstallDir  = env.getOrNull("VCINSTALLDIR");
	fromEnv.vcToolsInstallDir = env.getOrNull("VCTOOLSINSTALLDIR");
	fromEnv.universalCrtDir = env.getOrNull("UniversalCRTSdkDir");
	fromEnv.windowsSdkDir = env.getOrNull("WindowsSdkDir");
	fromEnv.universalCrtVersion = env.getOrNull("UCRTVersion");
	fromEnv.windowsSdkVersion = env.getOrNull("WindowsSDKVersion");


	if (!msvc.detect(ref fromEnv, out vsInstalls)) {
		drv.info("couldn't find visual studio installation falling back to env vars");
		vars.getDirsFromEnv(drv, env);
		return;
	}

	// Advanced Visual Studio Selection Algorithm Copyright Bernard Helyer, Donut Steel (@todo)
	vsInstall := vsInstalls[0];

	vars.msvcVer      = vsInstall.ver;
	vars.dirVCInstall = vsInstall.vcInstallDir;
	vars.dirUCRT      = vsInstall.universalCrtDir;
	vars.dirWinSDK    = vsInstall.windowsSdkDir;
	vars.numUCRT      = vsInstall.universalCrtVersion;
	vars.numWinSDK    = vsInstall.windowsSdkVersion;
	vars.oldLib       = vsInstall.lib;
	vars.oldPath      = env.getOrNull("PATH");
	if (vsInstall.linkerPath !is null) {
		vars.path ~= vsInstall.linkerPath;
	}
}

fn getDirsFromEnv(ref vars: VarsForMSVC, drv: Driver, env: Environment)
{
	vsInstalls: msvc.Result[];
	fromEnv: msvc.FromEnv;
	fromEnv.vcInstallDir  = env.getOrNull("VCINSTALLDIR");
	fromEnv.vcToolsInstallDir = env.getOrNull("VCTOOLSINSTALLDIR");
	fromEnv.universalCrtDir = env.getOrNull("UniversalCRTSdkDir");
	fromEnv.windowsSdkDir = env.getOrNull("WindowsSdkDir");
	fromEnv.universalCrtVersion = env.getOrNull("UCRTVersion");
	fromEnv.windowsSdkVersion = env.getOrNull("WindowsSDKVersion");

	if (!msvc.detect(ref fromEnv, out vsInstalls)) {
		drv.info("couldn't find visual studio installation falling back to env vars");
		return;
	}

	// Advanced Visual Studio Selection Algorithm Copyright Bernard Helyer, Donut Steel (@todo)
	vsInstall := vsInstalls[0];

	vars.msvcVer      = vsInstall.ver;
	vars.dirVCInstall = vsInstall.vcInstallDir;
	vars.dirUCRT      = vsInstall.universalCrtDir;
	vars.dirWinSDK    = vsInstall.windowsSdkDir;
	vars.numUCRT      = vsInstall.universalCrtVersion;
	vars.numWinSDK    = vsInstall.windowsSdkVersion;
	vars.oldLib       = vsInstall.lib;
	if (vsInstall.linkerPath !is null) {
		vars.path ~= vsInstall.linkerPath;
	}

	vars.oldInc  = env.getOrNull("INCLUDE");
	vars.oldLib  = env.getOrNull("LIB");
	vars.oldPath = env.getOrNull("PATH");
}

fn fillInListsForMSVC(ref vars: VarsForMSVC)
{
	vars.tPath(format("%s/bin/x86", vars.dirWinSDK));
	vars.tPath(format("%s/bin/x64", vars.dirWinSDK));

	final switch (vars.msvcVer) with (msvc.VisualStudioVersion) {
	case Unknown, MaxVersion:
		break;
	case V2015:
		vars.tPath(format("%s/BIN/amd64", vars.dirVCInstall));
		vars.tPath(format("%s/VCPackages", vars.dirVCInstall));
		vars.tInc(format("%s/INCLUDE", vars.dirVCInstall));
		vars.tLib(format("%s/LIB/amd64", vars.dirVCInstall));
		break;
	case V2017:
		vars.tPath(format("%s/bin/HostX64/x64", vars.dirVCInstall));
		vars.tInc(format("%s/ATLMFC/include", vars.dirVCInstall));
		vars.tInc(format("%s/include", vars.dirVCInstall));
		vars.tLib(format("%s/ATLMFC/lib/x64", vars.dirVCInstall));
		vars.tLib(format("%s/lib/x64", vars.dirVCInstall));
		break;
	}

	vars.tInc(format("%s/Include/%s/ucrt", vars.dirUCRT, vars.numUCRT));
	vars.tInc(format("%s/Include/%s/shared", vars.dirWinSDK, vars.numWinSDK));
	vars.tInc(format("%s/Include/%s/um", vars.dirWinSDK, vars.numWinSDK));
	vars.tInc(format("%s/Include/%s/winrt", vars.dirWinSDK, vars.numWinSDK));

	vars.tLib(format("%s/Lib/%s/ucrt/x64", vars.dirUCRT, vars.numUCRT));
	vars.tLib(format("%s/Lib/%s/um/x64", vars.dirWinSDK, vars.numWinSDK));
}

fn diffVars(drv: Driver, l: VarsForMSVC, r: VarsForMSVC)
{
	if (r.dirVCInstall != l.dirVCInstall &&
	    (r.dirVCInstall != null || l.dirVCInstall != null)) {
		drv.info("dirVCInstall");
		drv.info("\tl: %s", l.dirVCInstall);
		drv.info("\tr: %s", r.dirVCInstall);
	}
	if (r.dirUCRT != l.dirUCRT &&
	    (r.dirUCRT != null || l.dirUCRT != null)) {
		drv.info("dirUCRT");
		drv.info("\tl: %s", l.dirUCRT);
		drv.info("\tr: %s", r.dirUCRT);
	}
	if (r.dirWinSDK != l.dirWinSDK &&
	    (r.dirWinSDK != null || l.dirWinSDK != null)) {
		drv.info("dirWinSDK");
		drv.info("\tl: %s", l.dirWinSDK);
		drv.info("\tr: %s", r.dirWinSDK);
	}
	if (r.numUCRT != l.numUCRT &&
	    (r.numUCRT != null || l.numUCRT != null)) {
		drv.info("numUCRT");
		drv.info("\tl: %s", l.numUCRT);
		drv.info("\tr: %s", r.numUCRT);
	}
	if (r.numWinSDK != l.numWinSDK &&
	    (r.numWinSDK != null || l.numWinSDK != null)) {
		drv.info("numWinSDK");
		drv.info("\tl: %s", l.numWinSDK);
		drv.info("\tr: %s", r.numWinSDK);
	}

	drv.info("inc");
	foreach (inc; l.inc) {
		drv.info("\tl: %s", inc);
	}
	foreach (inc; r.inc) {
		drv.info("\tr: %s", inc);
	}

	drv.info("lib");
	foreach (lib; l.lib) {
		drv.info("\tl: %s", lib);
	}
	foreach (lib; r.lib) {
		drv.info("\tr: %s", lib);
	}

	drv.info("path");
	foreach (path; l.path) {
		drv.info("\tl: %s", path);
	}
	foreach (path; r.path) {
		drv.info("\tr: %s", path);
	}
}

/*!
 * Used to compare INCLUDE and LIB env vars,
 * badly deals with case sensitivity.
 */
fn compareOldAndNew(oldPath: string, newPath: string) bool
{
	if (oldPath is null) {
		return false;
	}

	// Dealing with case sensitivity on windows.
	version (Windows) {
		return oldPath.toLower() != newPath.toLower();
	} else {
		return oldPath != newPath;
	}
}

fn genAndCheckEnv(ref vars: VarsForMSVC, drv: Driver, out inc: string, out lib: string, out path: string)
{
	// Make and check the INCLUDE var.
	inc = join(vars.inc, ";") ~ ";";
	if (compareOldAndNew(vars.oldInc, inc)) {
		drv.info("env INCLUDE differers (using given)\ngiven: %s\n ours: %s", vars.oldInc, inc);
		inc = vars.oldInc;
	}

	// Make and check the LIB var.
	lib = join(vars.lib, ";") ~ ";";
	if (compareOldAndNew(vars.oldLib, lib)) {
		drv.info("env LIB differers (using given)\ngiven: %s\n ours: %s", vars.oldLib, lib);
		lib = vars.oldLib;
	}

	// Add any paths in vars.path to the system PATH, if it's not in there to begin with.
	systemPaths := split(vars.oldPath, ";");
	pathsToAdd := new string[](vars.path.length);
	addedPaths: size_t;
	foreach (vsPath; vars.path) {
		addThisPath := true;
		foreach (systemPath; systemPaths) {
			if (vsPath.toLower() == systemPath.toLower()) {
				addThisPath = false;
				break;
			}
		}
		if (!addThisPath) {
			continue;
		}
		pathsToAdd[addedPaths++] = vsPath;
	}
	pathsToAdd = pathsToAdd[0 .. addedPaths];

	path = vars.oldPath;
	foreach (addPath; pathsToAdd) {
		path = new "${addPath};${path}";
	}
}

fn addCommonLinkerArgsMSVC(config: Configuration, linker: Command)
{
	if (!config.isRelease) {
		linker.args ~= "/debug";
	}

	linker.args ~= [
		"/nologo",
		"/defaultlib:libcmt",
		"/defaultlib:oldnames",
		"legacy_stdio_definitions.lib",
	];
}


/*
 *
 * GDC
 *
 */

fn doGDC(drv: Driver, config: Configuration) bool
{
	fromArgs: gdc.FromArgs;
	results: gdc.Result[];
	result: gdc.Result;

	// Setup the path.
	path := config.env.getOrNull("PATH");
	gdc.detectFromPath(path, out results);

	// Did we get anything from the path?
	fillIfFound(drv, config, GdcName, out fromArgs.cmd, out fromArgs.args);
	if (gdc.detectFromArgs(ref fromArgs, out result)) {
		results = result ~ results;
	}

	// Find a good a result from the one that the detection code found.
	found := false;
	foreach (res; results) {
		// GDC 7 is a known bad.
		if (res.ver.major == 7) {
			continue;
		}

		// Add any extra arguments needed.
		gdc.addArgs(ref res, config.arch, config.platform, out result);

		// Found! :D
		found = true;
	}

	if (!found) {
		return false;
	}

	// Do that adding.
	c := config.addTool(GdcName, result.cmd, result.args);
	drv.infoCmd(config, c, result.from);
	return true;
}

fn doRDMD(drv: Driver, config: Configuration) bool
{
	fromArgs: rdmd.FromArgs;
	results: rdmd.Result[];
	result: rdmd.Result;

	// Setup the path.
	path := config.env.getOrNull("PATH");
	rdmd.detectFromPath(path, out results);

	// Did we get anything from the path?
	fillIfFound(drv, config, RdmdName, out fromArgs.cmd, out fromArgs.args);
	if (rdmd.detectFromArgs(ref fromArgs, out result)) {
		results = result ~ results;
	}

	// Didn't find any.
	if (results.length == 0) {
		return false;
	}

	// Add any extra arguments needed.s
	rdmd.addArgs(ref results[0], config.arch, config.platform, out result);

	// Do that adding.
	c := config.addTool(RdmdName, result.cmd, result.args);
	drv.infoCmd(config, c, result.from);
	return true;
}

fn doNASM(drv: Driver, config: Configuration) bool
{
	fromArgs: nasm.FromArgs;
	results: nasm.Result[];
	result: nasm.Result;

	// Setup the path.
	path := config.env.getOrNull("PATH");
	nasm.detectFromPath(path, out results);

	// Did we get anything from the path?
	fillIfFound(drv, config, NasmName, out fromArgs.cmd, out fromArgs.args);
	if (nasm.detectFromArgs(ref fromArgs, out result)) {
		results = result ~ results;
	}

	// Didn't find any.
	if (results.length == 0) {
		return false;
	}

	// Add any extra arguments needed.s
	nasm.addArgs(ref results[0], config.arch, config.platform, out result);

	// Do that adding.
	c := config.addTool(NasmName, result.cmd, result.args);
	drv.infoCmd(config, c, result.from);
	return true;
}

/*
 *
 * Fill in configuration.
 *
 */

fn fillInConfigCommands(drv: Driver, config: Configuration)
{
	volta := drv.getCmd(config.isBootstrap, VoltaName);
	if (volta !is null) {
		volta.print = VoltaPrint;
	}

	if (config.isBootstrap) {
		// Get the optional GDC and or RDMD command.

		config.rdmdCmd = config.getTool(RdmdName);
		if (config.rdmdCmd !is null) {
			config.rdmdCmd.print = BootRdmdPrint;
		}

		config.gdcCmd = config.getTool(GdcName);
		if (config.gdcCmd !is null) {
			config.gdcCmd.print = BootGdcPrint;
		}

		// Done now.
		return;
	}

	config.linkerCmd = config.getTool(LinkerName);
	config.clangCmd = config.getTool(ClangName);
	config.nasmCmd = config.getTool(NasmName);
	config.ccCmd = config.getTool(CCName);

	assert(config.linkerCmd !is null);
	assert(config.clangCmd !is null);
	assert(config.nasmCmd !is null);
	assert(config.ccCmd !is null);

	config.clangCmd.print = ClangPrint;
	config.nasmCmd.print = NasmPrint;
	config.ccCmd.print = ClangPrint;
	config.ccKind = CCKind.Clang;

	final switch (config.platform) with (Platform) {
	case MSVC:
		config.linkerCmd.print = LinkPrint;
		config.linkerKind = LinkerKind.Link;
		break;
	case Metal, Linux, OSX:
		config.linkerCmd.print = ClangPrint;
		config.linkerKind = LinkerKind.Clang;
		break;
	}
}


/*
 *
 * Helpers.
 *
 */

fn makeCommandFromPath(config: Configuration, cmd: string, name: string) Command
{
	cmd = searchPath(config.env.getOrNull("PATH"), cmd);
	if (cmd is null) {
		return null;
	}

	c := new Command();
	c.cmd = cmd;
	c.name = name;
	return c;
}

fn fillIfFound(drv: Driver, config: Configuration, name: string, out cmd: string, out args: string[])
{
	c := drv.getCmd(config.isBootstrap, name);
	if (c is null) {
		return;
	}
	cmd = c.cmd;
	args = c.args;
}
