// Copyright 2016-2018, Jakob Bornecrantz.
// SPDX-License-Identifier: BSL-1.0
/*!
 * Logic for setting up configs.
 */
module battery.policy.config;

import watt.io.file : isDir;
import watt.conv : toLower;
import watt.text.string : join, split, endsWith;
import watt.text.format : format;
import watt.text.path : normalisePath;
import watt.process : retrieveEnvironment, Environment;
import battery.interfaces;
import battery.policy.tools;
import battery.util.path : searchPath;

static import battery.util.log;

import gdc = battery.detect.gdc;
import ldc = battery.detect.ldc;
import llvm = battery.detect.llvm;
import rdmd = battery.detect.rdmd;
import nasm = battery.detect.nasm;
import msvc = battery.detect.msvc;
import volta = battery.detect.volta;


/*!
 * So we get the right prefix on logged messages.
 */
global log: battery.util.log.Logger = {"config"};


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
		
		// Failing that, give LDC a try.
		if (doLDC(drv, config)) {
			return;
		}

		// Fallback to RDMD.
		if (doRDMD(drv, config)) {
			return;
		}

		drv.abort("Did not find any bootstrap compiler (GDC) or (RDMD)");
		return;
	default:
	}

	final switch (config.platform) with (Platform) {
	case MSVC:
		// Always setup a basic LLVM toolchain.
		doToolChainLLVM(drv, config, UseAsLinker.NO);

		// Overwrite the LLVM toolchain a tiny bit.
		if (config.isCross) {
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
	doVolta(drv, config);

	final switch (config.arch) with (Arch) {
	case AArch64, ARMHF: break;
	case X86, X86_64:
		// NASM is needed for RT on X86 & X86_64.
		doNASM(drv, config);
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
		copyIfNotSet("VCTOOLSINSTALLDIR");
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

fn logNeeded(ref need: llvm.Needed, config: Configuration)
{
	info := new "${config.arch}-${config.platform}${config.isBootstrap ? \" (bootstrap)\" : \"\"}";

	if (!need.config &&
	    !need.ar &&
	    !need.clang &&
	    !need.ld &&
	    !need.link &&
	    !need.wasm) {
		log.info(new "Nothing from LLVM is needed ${info}");
	}

	str := new "For ${info} we need:";
	if (need.config) { str ~= "\n\tllvm-config"; }
	if (need.clang) { str ~= "\n\tclang"; }
	if (need.ar) { str ~= "\n\tllvm-ar"; }
	if (need.link) { str ~= "\n\tllvm-link"; }
	if (need.ld) { str ~= "\n\tlld"; }
	if (need.wasm) { str ~= "\n\twasm-ld"; }
	log.info(str);
}

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

fn logMissingNeeded(ref res: llvm.Result, cmd: string)
{
	log.info(new "Needed cmd '${cmd}' was not found in LLVM-${res.ver} result from ${res.from}.");
}

fn hasNeeded(ref res: llvm.Result, ref need: llvm.Needed) bool
{
	bool ok = true;
	if (need.config && (res.configCmd is null)) {
		res.logMissingNeeded("llvm-config");
		ok = false;
	}
	if (need.clang && (res.clangCmd is null)) {
		res.logMissingNeeded("clang");
		ok = false;
	}
	if (need.ar && (res.arCmd is null)) {
		res.logMissingNeeded("llvm-ar");
		ok = false;
	}
	if (need.link && (res.linkCmd is null)) {
		res.logMissingNeeded("llvm-link");
		ok = false;
	}
	if (need.ld && (res.ldCmd is null)) {
		res.logMissingNeeded("lld");
		ok = false;
	}
	if (need.wasm && (res.wasmCmd is null)) {
		res.logMissingNeeded("wasm-ld");
		ok = false;
	}
	return ok;
}

enum UseAsLinker
{
	NO,
	YES,
}

fn pickLLVM(drv: Driver, config: Configuration,
            out need: llvm.Needed, out result: llvm.Result) bool
{
	fromArgs: llvm.FromArgs;
	results: llvm.Result[];
	temp: llvm.Result;

	// Needed to detect.
	path := config.env.getOrNull("PATH");
	llvmConfs := [config.llvmConf];

	// Main detection.
	llvm.detectFrom(path, llvmConfs, out results);

	// Add from args.
	fillIfFound(drv, config, LLVMConfigName, out fromArgs.configCmd, out fromArgs.configArgs);
	fillIfFound(drv, config, LLVMArName, out fromArgs.arCmd, out fromArgs.arArgs);
	fillIfFound(drv, config, ClangName, out fromArgs.clangCmd, out fromArgs.clangArgs);
	fillIfFound(drv, config, LDLLDName, out fromArgs.ldCmd, out fromArgs.ldArgs);
	fillIfFound(drv, config, LLDLinkName, out fromArgs.linkCmd, out fromArgs.linkArgs);
	fillIfFound(drv, config, WasmLLDName, out fromArgs.wasmCmd, out fromArgs.wasmArgs);
	if (llvm.detectFromArgs(ref fromArgs, out temp)) {
		results = temp ~ results;
	}

	// Did we get anything from the BatteryConfig.
	if (llvm.detectFromBatConf(ref config.batConf, out temp)) {
		results = temp ~ results;
	}

	// What do we need?
	need.fillInNeeded(config);
	need.logNeeded(config);

	// Loop the results.
	foreach (i, ref res; results) {
		if (!res.hasNeeded(ref need)) {
			log.info(new "Rejecting result #${i + 1} (LLVM-${res.ver}) result from ${res.from} because of missing commands.");
			continue;
		}

		log.info(new "Selecting result #${i + 1} (LLVM-${res.ver}) from ${res.from} for ${config.arch}-${config.platform}.");

		llvm.addArgs(ref res, config.arch, config.platform, out result);
		return true;
	}

	log.info(new "Could not find any LLVM toolchain for ${config.arch}-${config.platform}.");

	return false;
}

fn doToolChainLLVM(drv: Driver, config: Configuration, useLinker: UseAsLinker)
{
	result: llvm.Result;
	need: llvm.Needed;

	// Pick the best suited LLVM toolchain found.
	if (!pickLLVM(drv, config, out need, out result)) {
		drv.abort("No valid LLVM Toolchains found!");
	}

	configCommand: Command;
	arCommand: Command;
	ldCommand: Command;
	linkCommand: Command;
	wasmCommand: Command;
	clang: Command;

	if (result.configCmd !is null) {
		configCommand = config.addTool(LLVMConfigName, result.configCmd, result.configArgs);
	}
	if (result.arCmd !is null) {
		arCommand = config.addTool(LLVMArName, result.arCmd, result.arArgs);
	}
	if (result.ldCmd !is null) {
		ldCommand = config.addTool(LDLLDName, result.ldCmd, result.ldArgs);
	}
	if (result.linkCmd !is null) {
		linkCommand = config.addTool(LLDLinkName, result.linkCmd, result.linkArgs);
	}
	if (result.wasmCmd !is null) {
		wasmCommand = config.addTool(WasmLLDName, result.wasmCmd, result.wasmArgs);
	}

	// If needed setup the linker command.
	linker: Command;
	if (useLinker) {
		linker = drv.getCmd(config.isBootstrap, LinkerName);

		// If linker was not given use clang as the linker.
		// Always add it to the config.
		if (linker is null) {
			args := result.clangArgs;
			if (result.ldCmd !is null) {
				args ~= "-fuse-ld=" ~ result.ldCmd;
			}
			linker = config.addTool(LinkerName, result.clangCmd, args);
		} else {
			linker = config.addTool(LinkerName, linker.cmd, linker.args);
		}
	}

	if (!config.isBootstrap) {
		// A tiny bit of sanity checking.
		assert(result.clangCmd !is null);

		// Setup clang and cc tools.
		clang = config.addTool(ClangName, result.clangCmd, result.clangArgs);
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
				linker.args ~= "-flto=thin";
			}
		}
	}

	config.llvmVersion = result.ver;

	drv.info("Using LLVM-%s toolchain from %s.", result.ver, result.from);
	if (configCommand !is null) drv.infoCmd(config, configCommand, result.from);
	if (clang         !is null) drv.infoCmd(config, clang,         result.from);
	if (arCommand     !is null) drv.infoCmd(config, arCommand,     result.from);
	if (ldCommand     !is null) drv.infoCmd(config, ldCommand,     result.from);
	if (linkCommand   !is null) drv.infoCmd(config, linkCommand,   result.from);
	if (wasmCommand   !is null) drv.infoCmd(config, wasmCommand,   result.from);
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
	//! How was this MSVC found?
	from: string;

	//! The cl.exe for this specific MSVC version.
	clCmd: string;
	//! The link.exe for this specific MSVC version.
	linkCmd: string;

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
	lib, inc, path: string;
	vars: VarsForMSVC;
	vars.getMSVCInfo(drv, outside);
	vars.fillInListsForMSVC();
	vars.genAndCheckEnv(drv, out inc, out lib, out path);

	config.env.set("INCLUDE", inc);
	config.env.set("LIB", lib);
	config.env.set("PATH", path);

	config.env.set("UniversalCRTSdkDir", vars.dirUCRT);
	config.env.set("WindowsSdkDir", vars.dirWinSDK);
	config.env.set("UCRTVersion", vars.numUCRT);
	config.env.set("WindowsSDKVersion", vars.numWinSDK);

	// Setup cl.exe
	cl := drv.getCmd(config.isBootstrap, CLName);
	clFrom := "args";
	if (cl !is null) {
		cl = config.addTool(CLName, cl.cmd, cl.args);
	} else if (vars.clCmd !is null) {
		cl = config.addTool(CLName, vars.clCmd, null);
		clFrom = vars.from;
	}

	// Setup link.exe
	link := drv.getCmd(config.isBootstrap, LinkName);
	linkFrom := "args";
	if (link !is null) {
		link = config.addTool(LinkName, link.cmd, link.args);
	} else if (vars.linkCmd !is null) {
		link = config.addTool(LinkName, vars.linkCmd, null);
		linkFrom = vars.from;
	}

	// First see if the linker is specified.
	linker := drv.getCmd(config.isBootstrap, LinkerName);
	linkerFrom := "args";

	// If it was not specified or found get 'lld-link' from the LLVM toolchain.
	if (linker is null) {
		linker = config.getTool(LLDLinkName);
		linkerFrom = "llvm";
	}

	// If it was not specified try getting from the MSVC installation.
	if (linker is null) {
		linker = link;
		linkerFrom = linkFrom;
	}

	// Abort if we don't have a linker.
	if (linker is null) {
		drv.abort("Could not find a valid system linker!\n\tNeed either lld-link.exe or link.exe command.");
	}

	// Always add it to the config.
	linker = config.addTool(LinkerName, linker.cmd, linker.args);

	// Always add the common arguments to the linker.
	addCommonLinkerArgsMSVC(config, linker);

	verStr := msvc.visualStudioVersionToString(vars.msvcVer);
	drv.info("Using Visual Studio Build Tools %s from %s.", verStr, vars.from);
	if (cl !is null)     drv.infoCmd(config, cl, clFrom);
	if (link !is null)   drv.infoCmd(config, link, linkFrom);
	if (linker !is null) drv.infoCmd(config, linker, linkerFrom);
}

fn doToolChainCrossMSVC(drv: Driver, config: Configuration, outside: Environment)
{
	assert(!config.isBootstrap);

	// First see if the linker is specified.
	linker := drv.getCmd(config.isBootstrap, LinkerName);
	linkerFrom := "args";

	// If it was not specified get 'lld-link' from the LLVM toolchain.
	if (linker is null) {
		linker = config.getTool(LLDLinkName);
		linkerFrom = "llvm";
	}

	// Just in case.
	if (linker is null) {
		drv.abort("Could not find any linker!");
	}

	// Always add it to the config.
	linker = config.addTool(LinkerName, linker.cmd, linker.args);

	// Always add the common arguments to the linker.
	addCommonLinkerArgsMSVC(config, linker);

	// Get the CC setup by the llvm toolchain.
	cc := config.getTool(CCName);
	assert(cc !is null);

	vars: VarsForMSVC;
	vars.getMSVCInfo(drv, outside);
	vars.fillInListsForMSVC();

	foreach (i; vars.inc) {
		cc.args ~= "-I" ~ i;
	}

	foreach (l; vars.lib) {
		linker.args ~= format("/LIBPATH:%s", l);
	}

	verStr := msvc.visualStudioVersionToString(vars.msvcVer);
	drv.info("Using Visual Studio Build Tools %s from %s.", verStr, vars.from);
	drv.infoCmd(config, linker, linkerFrom);
}

fn getMSVCInfo(ref vars: VarsForMSVC, drv: Driver, env: Environment)
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
		drv.abort("Couldn't find visual studio installation.");
	}

	// Advanced Visual Studio Selection Algorithm Copyright Bernard Helyer, Donut Steel (@todo)
	vsInstall := vsInstalls[0];

	vars.oldInc  = env.getOrNull("INCLUDE");
	vars.oldLib  = env.getOrNull("LIB");
	vars.oldPath = env.getOrNull("PATH");

	vars.msvcVer      = vsInstall.ver;
	vars.from         = vsInstall.from;

	vars.clCmd        = vsInstall.clCmd;
	vars.linkCmd      = vsInstall.linkCmd;

	vars.dirVCInstall = vsInstall.vcInstallDir;
	vars.dirUCRT      = vsInstall.universalCrtDir;
	vars.dirWinSDK    = vsInstall.windowsSdkDir;
	vars.numUCRT      = vsInstall.universalCrtVersion;
	vars.numWinSDK    = vsInstall.windowsSdkVersion;
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
	case V2019: // Maybe?
	case V2022: // Maybe?
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
	vars.tInc(format("%s/Include/%s/cppwinrt", vars.dirWinSDK, vars.numWinSDK));

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
	inc = join(vars.inc, ";");
	if (vars.oldInc.endsWith(";")) {
		inc ~= ";";
	}

	if (compareOldAndNew(vars.oldInc, inc)) {
		drv.info("env INCLUDE differers (using given)\ngiven: %s\n ours: %s", vars.oldInc, inc);
		inc = vars.oldInc;
	}

	// Make and check the LIB var.
	lib = join(vars.lib, ";");
	if (vars.oldLib.endsWith(";")) {
		lib ~= ";";
	}

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

	// Search the path last.
	path := config.env.getOrNull("PATH");
	gdc.detectFromPath(path, out results);

	// Did we get anything from the BatteryConfig?
	if (gdc.detectFromBatConf(ref config.batConf, out result)) {
		results = result ~ results;
	}

	// Did we get anything from the args?
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

	// Do that adding, result now holds all of the info.
	c := config.addTool(GdcName, result.cmd, result.args);
	drv.infoCmd(config, c, result.from);
	return true;
}

fn doLDC(drv: Driver, config: Configuration) bool
{
	fromArgs: ldc.FromArgs;
	results: ldc.Result[];
	result: ldc.Result;

	// Search the path.
	path := config.env.getOrNull("PATH");
	ldc.detectFromPath(path, out results);

	// Did we get anything from the BatteryConfig?
	if (ldc.detectFromBatConf(ref config.batConf, out result)) {
		results = result ~ results;
	}

	// Did we get anything from the args?
	fillIfFound(drv, config, LdcName, out fromArgs.cmd, out fromArgs.args);
	if (ldc.detectFromArgs(ref fromArgs, out result)) {
		results = result ~ results;
	}

	// Didn't find any.
	if (results.length == 0) {
		return false;
	}

	// Add any extra arguments needed.
	ldc.addArgs(ref results[0], config.arch, config.platform, out result);

	// Add result to the config.
	c := config.addTool(LdcName, result.cmd, result.args);
	drv.infoCmd(config, c, result.from);
	return true;
}

fn doRDMD(drv: Driver, config: Configuration) bool
{
	fromArgs: rdmd.FromArgs;
	results: rdmd.Result[];
	result: rdmd.Result;

	// Search the path.
	path := config.env.getOrNull("PATH");
	rdmd.detectFromPath(path, out results);

	// Did we get anything from the BatteryConfig?
	if (rdmd.detectFromBatConf(ref config.batConf, out result)) {
		results = result ~ results;
	}

	// Did we get anything from the args?
	fillIfFound(drv, config, RdmdName, out fromArgs.cmd, out fromArgs.args);
	if (rdmd.detectFromArgs(ref fromArgs, out result)) {
		results = result ~ results;
	}

	// Didn't find any.
	if (results.length == 0) {
		return false;
	}

	// Add any extra arguments needed, select the first one!
	rdmd.addArgs(ref results[0], config.arch, config.platform, out result);

	// Do that adding, result now holds all of the info.
	c := config.addTool(RdmdName, result.cmd, result.args);
	drv.infoCmd(config, c, result.from);
	return true;
}

fn doNASM(drv: Driver, config: Configuration) bool
{
	fromArgs: nasm.FromArgs;
	results: nasm.Result[];
	result: nasm.Result;

	// Search the path.
	path := config.env.getOrNull("PATH");
	nasm.detectFromPath(path, out results);

	// Did we get anything from the BatteryConfig?
	if (nasm.detectFromBatConf(ref config.batConf, out result)) {
		results = result ~ results;
	}

	// Did we get anything from the args?
	fillIfFound(drv, config, NasmName, out fromArgs.cmd, out fromArgs.args);
	if (nasm.detectFromArgs(ref fromArgs, out result)) {
		results = result ~ results;
	}

	// Didn't find any.
	if (results.length == 0) {
		return false;
	}

	// Add any extra arguments needed, select the first one!
	nasm.addArgs(ref results[0], config.arch, config.platform, out result);

	// Do that adding, result now holds all of the info.
	c := config.addTool(NasmName, result.cmd, result.args);
	drv.infoCmd(config, c, result.from);
	return true;
}

fn doVolta(drv: Driver, config: Configuration) bool
{
	fromArgs: volta.FromArgs;
	results: volta.Result[];
	result: volta.Result;

	// Do not do any path detection.

	// Did we get anything from the BatteryConfig?
	if (volta.detectFromBatConf(ref config.batConf, out result)) {
		results = result ~ results;
	}

	// Did we get anything from the args?
	fillIfFound(drv, config, VoltaName, out fromArgs.cmd, out fromArgs.args);
	if (volta.detectFromArgs(ref fromArgs, out result)) {
		results = result ~ results;
	}

	// Didn't find any.
	if (results.length == 0) {
		return false;
	}

	// Add any extra arguments needed, select the first one!
	volta.addArgs(ref results[0], config.arch, config.platform, out result);

	// Do that adding, result now holds all of the info.
	c := config.addTool(VoltaName, result.cmd, result.args);
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

		config.ldcCmd = config.getTool(LdcName);
		if (config.ldcCmd !is null) {
			config.ldcCmd.print = BootLdcPrint;
		}

		// Done now.
		return;
	}

	config.linkerCmd = config.getTool(LinkerName);
	config.clangCmd = config.getTool(ClangName);
	config.ccCmd = config.getTool(CCName);

	assert(config.linkerCmd !is null);
	assert(config.clangCmd !is null);
	assert(config.ccCmd !is null);

	config.clangCmd.print = ClangPrint;
	config.ccCmd.print = ClangPrint;
	config.ccKind = CCKind.Clang;

	final switch (config.arch) with (Arch) {
	case ARMHF, AArch64:
		break;
	case X86, X86_64:
		config.nasmCmd = config.getTool(NasmName);
		assert(config.nasmCmd !is null);
		config.nasmCmd.print = NasmPrint;
		break;
	}

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
