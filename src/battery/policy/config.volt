// Copyright © 2016, Jakob Bornecrantz.  All rights reserved.
// See copyright notice in src/battery/license.volt (BOOST ver. 1.0).
/**
 * Logic for setting up configs.
 */
module battery.policy.config;

import watt.io.file : isDir;
import watt.conv : toLower;
import watt.text.string : join, split;
import watt.text.format : format;
import watt.text.path : normalisePath;
import watt.process : retrieveEnvironment, Environment;
import battery.interfaces;
import battery.configuration;
import battery.policy.tools;
import battery.util.path : searchPath;
import detect.visualStudio;


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
		drv.info("Various tools needed by compile.");

		// Get RDMD if we are bootstrapping.
		drvRdmd := drv.fillInCommand(config, RdmdName);
		config.addTool(RdmdName, drvRdmd.cmd, drvRdmd.args);
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
		drv.infoCmd(config, drvVolta, true);
	}

	// NASM is needed for RT.
	drvNasm := drv.fillInCommand(config, NasmName);
	config.addTool(NasmName, drvNasm.cmd, drvNasm.args);
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


struct LLVMConfig
{
public:
	drv: Driver;
	suffix: string;

	config: Command;
	ar: Command;
	clang: Command;
	ld: Command;
	link: Command;

	drvAll: bool;
	drvConfig, drvAr, drvClang, drvLd, drvLink: bool;
	needConfig, needAr, needClang, needLd, needLink: bool;


public:
	fn fillInNeeded(config: Configuration)
	{
		// For Windows llvm-config is not needed.
		version (!Windows) {
			this.needConfig = true;
		}

		// Bootstrap does not require anything more.
		if (config.isBootstrap) {
			return;
		}

		// Need clang for the rest.
		this.needClang = true;

		// Platform specific.
		final switch (config.platform) with (Platform) {
		case MSVC:
			this.needLink = config.isLTO || config.isCross;
			this.needAr = config.isLTO;
			break;
		case Metal, Linux:
			this.needLd = config.isLTO;
			this.needAr = config.isLTO;
			break;
		case OSX:
			this.needAr = config.isLTO;
			break;
		}
	}

	fn fillInFromDriver(drv: Driver, config: Configuration)
	{
		this.drv = drv;
		fillInNeeded(config);

		this.config = drv.getCmd(config.isBootstrap, LLVMConfigName);
		this.ar =     drv.getCmd(config.isBootstrap, LLVMArName);
		this.clang =  drv.getCmd(config.isBootstrap, ClangName);
		this.ld =     drv.getCmd(config.isBootstrap, LDLLDName);
		this.link =   drv.getCmd(config.isBootstrap, LLDLinkName);

		this.drvConfig = this.config !is null;
		this.drvAr = this.ar !is null;
		this.drvClang = this.clang !is null;
		this.drvLd = this.ld !is null;
		this.drvLink = this.link !is null;
		this.drvAll = hasNeeded;
	}

	fn fillInFromPath(config: Configuration, suffix: string) bool
	{
		this.suffix = suffix;

		if (this.config is null) {
			this.config = config.makeCommandFromPath(LLVMConfigCommand ~ suffix, LLVMConfigName);
		}
		if (this.ar is null) {
			this.ar = config.makeCommandFromPath(LLVMArCommand ~ suffix, LLVMArName);
		}
		if (this.clang is null) {
			this.clang = config.makeCommandFromPath(ClangCommand ~ suffix, ClangName);
			if (this.clang !is null) {
				addClangArgs(drv, config, this.clang);
			}
		}
		if (this.ld is null) {
			this.ld = config.makeCommandFromPath(LDLLDCommand ~ suffix, LDLLDName);
		}
		if (this.link is null) {
			this.link = config.makeCommandFromPath(LLDLinkCommand ~ suffix, LLDLinkName);
		}

		return hasNeeded;
	}

	@property fn hasNeeded() bool
	{
		if (needConfig && (this.config is null)) return false;
		if (needClang && (this.clang is null)) return false;
		if (needAr && (this.ar is null)) return false;
		if (needLink && (this.link is null)) return false;
		if (needLd && (this.ld is null)) return false;
		return true;
	}

	fn printMissing()
	{
		shouldPrint := (suffix is null) ||
			(needConfig && !drvConfig && config !is null) ||
			(needClang && !drvClang && clang !is null) ||
			(needAr && !drvAr && ar !is null) ||
			(needLink && !drvLink && link !is null) ||
			(needLd && !drvLd && ld !is null);
		if (!shouldPrint) {
			drv.info("llvm%s toolchain not detected at all!", suffix);
			return;
		}

		tmp := suffix is null ? "generic " : null;
		drv.info("%sllvm%s toolchain partially detected!", tmp, suffix);
		if (needConfig) {
			printFoundOrMissingCmd(LLVMConfigCommand, config);
		}
		if (needClang) {
			printFoundOrMissingCmd(ClangCommand, clang);
		}
		if (needAr) {
			printFoundOrMissingCmd(LLVMArCommand, ar);
		}
		if (needLink) {
			printFoundOrMissingCmd(LDLLDCommand, link);
		}
		if (needLd) {
			printFoundOrMissingCmd(LLDLinkCommand, ld);
		}
	}

	fn printFoundOrMissingCmd(name: string, cmd: Command)
	{
		if (cmd !is null) {
			printFoundCmd(name, cmd.cmd);
		} else {
			printMissingCmd(name);
		}
	}

	fn printMissingCmd(cmd: string)
	{
		drv.info("\t%s%s missing!", cmd, suffix);
	}

	fn printFoundCmd(cmd: string, path: string)
	{
		drv.info("\t%s%s found '%s'", cmd, suffix, path);
	}
}

enum UseAsLinker
{
	NO,
	YES,
}

fn doToolChainLLVM(drv: Driver, config: Configuration, useLinker: UseAsLinker)
{
	llvm60, llvm50, llvm40, llvm39, llvm: LLVMConfig;
	llvm.fillInFromDriver(drv, config);

	llvm60 = llvm50 = llvm40 = llvm39 = llvm;

	if (llvm.drvAll) {
		// Nothing todo
	} else if (llvm.fillInFromPath(config, null)) {
		// Nothing todo
	} else if (llvm60.fillInFromPath(config, "-6.0")) {
		llvm = llvm60;
	} else if (llvm50.fillInFromPath(config, "-5.0")) {
		llvm = llvm50;
	} else if (llvm40.fillInFromPath(config, "-4.0")) {
		llvm = llvm40;
	} else if (llvm39.fillInFromPath(config, "-3.9")) {
		llvm = llvm39;
	} else {
		llvm.printMissing();
		llvm60.printMissing();
		llvm50.printMissing();
		llvm40.printMissing();
		llvm39.printMissing();
		drv.abort("could not find a valid llvm toolchain");
	}

	if (llvm.config !is null && llvm.needConfig) {
		config.addTool(LLVMConfigName, llvm.config.cmd, llvm.config.args);
	}
	if (llvm.ar !is null && llvm.needAr) {
		config.addTool(LLVMArName, llvm.ar.cmd, llvm.ar.args);
	}
	if (llvm.ld !is null && llvm.needLd) {
		config.addTool(LDLLDName, llvm.ld.cmd, llvm.ld.args);
	}
	if (llvm.link !is null && llvm.needLink) {
		config.addTool(LLDLinkName, llvm.link.cmd, llvm.link.args);
	}

	// If needed setup the linker command.
	linker: Command;
	if (useLinker) {
		linker = drv.getCmd(config.isBootstrap, LinkerName);

		// If linker was not given use clang as the linker.
		if (linker is null) {
			linker = llvm.clang;
		}

		// Always add it to the config.
		linker = config.addTool(LinkerName, linker.cmd, linker.args);
	}

	if (!config.isBootstrap) {
		// A tiny bit of sanity checking.
		assert(llvm.clang !is null);

		// Setup clang and cc tools.
		clang := config.addTool(ClangName, llvm.clang.cmd, llvm.clang.args);
		cc := config.addTool(CCName, llvm.clang.cmd, llvm.clang.args);

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

	drv.info("Using LLVM%s toolchain from %s.", llvm.suffix, llvm.drvAll ? "arguments" : "path");
	if (llvm.config !is null && llvm.needConfig) drv.infoCmd(config, llvm.config, llvm.drvConfig);
	if (llvm.clang  !is null && llvm.needClang)  drv.infoCmd(config, llvm.clang,  llvm.drvClang);
	if (llvm.ar     !is null && llvm.needAr)     drv.infoCmd(config, llvm.ar,     llvm.drvAr);
	if (llvm.ld     !is null && llvm.needLd)     drv.infoCmd(config, llvm.ld,     llvm.drvLd);
	if (llvm.link   !is null && llvm.needLink)   drv.infoCmd(config, llvm.link,   llvm.drvLink);
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
	msvcVer: VisualStudioVersion;

	//! Install directory for compiler and linker, from @p VCINSTALLDIR env.
	dirVC: string;
	//! Install directory for compiler and linker, from @p VCTOOLSINSTALLDIR env.
	dirVCTools: string;

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

	verStr := vars.msvcVer.visualStudioVersionToString();
	drv.info("Using Visual Studio Build Tools %s.", verStr);
	if (linkerFromLLVM) {
		drv.info("\tcmd linker: Linking with lld-link.exe from LLVM toolchain.");
	} else {
		drv.infoCmd(config, linker, linkerFromArg);
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

	verStr := vars.msvcVer.visualStudioVersionToString();
	drv.info("Using MSVC %s from the enviroment.", verStr);
	if (linkerFromArg) {
		drv.infoCmd(config, linker, linkerFromArg);
	}
}

fn getDirsFromRegistry(ref vars: VarsForMSVC, drv: Driver, env: Environment)
{
	vsInstalls := getVisualStudioInstallations();
	if (vsInstalls.length == 0) {
		drv.abort("couldn't find visual studio installation");
	}

	// Advanced Visual Studio Selection Algorithm Copyright Bernard Helyer, Donut Steel (@todo)
	vsInstall := vsInstalls[0];

	vars.msvcVer   = vsInstall.ver;
	vars.dirVC     = vsInstall.vcInstallDir;
	vars.dirUCRT   = vsInstall.universalCrtDir;
	vars.dirWinSDK = vsInstall.windowsSdkDir;
	vars.numUCRT   = vsInstall.universalCrtVersion;
	vars.numWinSDK = vsInstall.windowsSdkVersion;
	vars.oldLib    = vsInstall.lib;
	vars.oldPath   = env.getOrNull("PATH");
	if (vsInstall.linkerPath !is null) {
		vars.path ~= vsInstall.linkerPath;
	}
}

fn getDirsFromEnv(ref vars: VarsForMSVC, drv: Driver, env: Environment)
{
	fn getOrWarn(name: string) string {
		value := env.getOrNull(name);
		if (value.length == 0) {
			drv.info("error: need to set env var '%s'", name);
		}
		return value;
	}

	vars.oldInc = env.getOrNull("INCLUDE");
	vars.oldLib = env.getOrNull("LIB");

	vars.dirVC = env.getOrNull("VCINSTALLDIR");
	vars.dirVCTools = env.getOrNull("VCTOOLSINSTALLDIR");

	if (vars.dirVCTools !is null) {
		vars.msvcVer = VisualStudioVersion.V2017;
	} else if (vars.dirVC !is null) {
		vars.msvcVer = VisualStudioVersion.V2015;
	} else {
		drv.info("error: Make sure you have VS Tools 2015 or 2017 installed.");
		drv.info("error: need to set env var 'VCINSTALLDIR' or 'VCTOOLSINSTALLDIR'.");
	}

	vars.dirUCRT = getOrWarn("UniversalCRTSdkDir");
	vars.dirWinSDK = getOrWarn("WindowsSdkDir");
	vars.numUCRT = getOrWarn("UCRTVersion");
	vars.numWinSDK = getOrWarn("WindowsSDKVersion");

	if ((vars.dirVC.length == 0 && vars.dirVCTools.length == 0) ||
	    vars.dirUCRT.length == 0 || vars.dirWinSDK.length == 0 ||
	    vars.numUCRT.length == 0 || vars.numWinSDK.length == 0) {
		drv.abort("missing environmental variable");
	}
}

fn fillInListsForMSVC(ref vars: VarsForMSVC)
{
	vars.tPath(format("%s/bin/x86", vars.dirWinSDK));
	vars.tPath(format("%s/bin/x64", vars.dirWinSDK));

	final switch (vars.msvcVer) with (VisualStudioVersion) {
	case Unknown, MaxVersion:
		break;
	case V2015:
		vars.tPath(format("%s/BIN/amd64", vars.dirVC));
		vars.tPath(format("%s/VCPackages", vars.dirVC));
		vars.tInc(format("%s/INCLUDE", vars.dirVC));
		vars.tLib(format("%s/LIB/amd64", vars.dirVC));
		break;
	case V2017:
		vars.tPath(format("%s/bin/HostX64/x64", vars.dirVCTools));
		vars.tInc(format("%s/ATLMFC/include", vars.dirVCTools));
		vars.tInc(format("%s/include", vars.dirVCTools));
		vars.tLib(format("%s/ATLMFC/lib/x64", vars.dirVCTools));
		vars.tLib(format("%s/lib/x64", vars.dirVCTools));
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
	if (r.dirVC != l.dirVC &&
	    (r.dirVC != null || l.dirVC != null)) {
		drv.info("dirVC");
		drv.info("\tl: %s", l.dirVC);
		drv.info("\tr: %s", r.dirVC);
	}
	if (r.dirVCTools != l.dirVCTools &&
	    (r.dirVCTools != null || l.dirVCTools != null)) {
		drv.info("dirVCTools");
		drv.info("\tl: %s", l.dirVCTools);
		drv.info("\tr: %s", r.dirVCTools);
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
		// Get the optional RDMD command.
		config.rdmdCmd = config.getTool(RdmdName);
		assert(config.rdmdCmd !is null);
		config.rdmdCmd.print = RdmdPrint;

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
	cmd = searchPath(cmd, config.env);
	if (cmd is null) {
		return null;
	}

	c := new Command();
	c.cmd = cmd;
	c.name = name;
	return c;
}
