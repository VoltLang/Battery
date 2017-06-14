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
import watt.process : retrieveEnvironment, Environment;
import battery.interfaces;
import battery.configuration;
import battery.policy.tools;
import battery.util.path : searchPath;


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

	drvVolta := drv.getCmd(config.isHost, "volta");
	if (drvVolta !is null) {
		config.addTool("volta", drvVolta.cmd, drvVolta.args);
		drv.infoCmd(config, drvVolta, true);
	}

	drvRdmd := drv.fillInCommand(config, RdmdName);
	drvNasm := drv.fillInCommand(config, NasmName);

	config.addTool(RdmdName, drvRdmd.cmd, drvRdmd.args);
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
		// Must always have clang.
		this.needClang = true;

		// For Windows llvm-config is not needed.
		version (!Windows) {
			this.needConfig = true;
		}

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
		fillInNeeded(config);

		this.config = drv.getCmd(config.isHost, LLVMConfigName);
		this.ar =     drv.getCmd(config.isHost, LLVMArName);
		this.clang =  drv.getCmd(config.isHost, ClangName);
		this.ld =     drv.getCmd(config.isHost, LDLLDName);
		this.link =   drv.getCmd(config.isHost, LLDLinkName);

		this.drvConfig = this.config !is null;
		this.drvAr = this.ar !is null;
		this.drvClang = this.clang !is null;
		this.drvLd = this.ld !is null;
		this.drvLink = this.link !is null;
		this.drvAll = hasNeeded;
	}

	fn fillFromPath(config: Configuration, suffix: string)
	{
		cmd: string;

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

	fn addSuffixedCmdIfOkay(config: Configuration, suffix: string) bool
	{
		test := this;
		test.suffix = suffix;
		test.fillFromPath(config, suffix);
		if (!test.hasNeeded) {
			return false;
		}
		this = test;
		return true;
	}
}

enum UseAsLinker
{
	NO,
	YES,
}

fn doToolChainLLVM(drv: Driver, config: Configuration, useLinker: UseAsLinker)
{
	llvm: LLVMConfig;
	llvm.drv = drv;
	llvm.fillInFromDriver(drv, config);

	if (!llvm.drvAll &&
	    !llvm.addSuffixedCmdIfOkay(config, null) &&
	    !llvm.addSuffixedCmdIfOkay(config, "-5.0") &&
	    !llvm.addSuffixedCmdIfOkay(config, "-4.0") &&
	    !llvm.addSuffixedCmdIfOkay(config, "-3.9")) {
		drv.abort("could not find a valid llvm toolchain");
	}

	assert(llvm.clang !is null);

	if (llvm.config !is null && llvm.needConfig) {
		config.addTool(LLVMConfigName, llvm.config.cmd, llvm.config.args);
	}
	if (llvm.ar !is null && llvm.needConfig) {
		config.addTool(LLVMArName, llvm.ar.cmd, llvm.ar.args);
	}
	if (llvm.ld !is null && llvm.needConfig) {
		config.addTool(LDLLDName, llvm.ld.cmd, llvm.ld.args);
	}
	if (llvm.link !is null && llvm.needConfig) {
		config.addTool(LLDLinkName, llvm.link.cmd, llvm.link.args);
	}

	// If needed setup the linker command.
	linker: Command;
	if (useLinker) {
		linker = drv.getCmd(config.isHost, LinkerName);

		// If linker was not given use clang as the linker.
		if (linker is null) {
			linker = llvm.clang;
		}

		// Always add it to the config.
		linker = config.addTool(LinkerName, linker.cmd, linker.args);
	}

	// Setup clang and cc tools.
	clang := config.addTool(ClangName, llvm.clang.cmd, llvm.clang.args);
	cc := config.addTool(CCName, llvm.clang.cmd, llvm.clang.args);

	// Add any extra arguments.
	if (config.isRelease) {
		clang.args ~= "-O3";
		cc.args ~= "-O3";
	} else { // Debug.
		cc.args ~= "-g";
	}

	if (config.isLTO) {
		clang.args ~= "-flto=thin";
		cc.args ~= "-flto=thin";
		if (linker !is null) {
			linker.args ~= "-flto=thin";
		}
	}

	drv.info("llvm%s toolchain was %s.", llvm.suffix, llvm.drvAll ? "from arguments" : "from path");
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
	fn tPath(dir: string) {
		dir = normalizePath(dir);
		if (isDir(dir)) {
			path ~= dir;
		}
	}

	fn tInc(dir: string) {
		dir = normalizePath(dir);
		if (isDir(dir)) {
			inc ~= dir;
		}
	}

	fn tLib(dir: string) {
		dir = normalizePath(dir);
		if (isDir(dir)) {
			lib ~= dir;
		}
	}
}

fn doToolChainNativeMSVC(drv: Driver, config: Configuration, outside: Environment)
{
	// First see if the linker is specified.
	linker := drv.getCmd(config.isHost, LinkerName);

	// If it was not specified try getting 'link.exe' from the path.
	if (linker is null) {
		linker = drv.fillInCommand(config, LinkName);
	}

	// Always add it to the config.
	assert(linker !is null);
	linker = config.addTool(LinkerName, linker.cmd, linker.args);

	// Get the CC setup by the llvm toolchain.
	cc := config.getTool(CCName);
	assert(cc !is null);

	vars: VarsForMSVC;
	getDirsFromEnv(drv, outside, ref vars);
	fillInListsForMSVC(ref vars);

	// Set the built env vars.
	config.env.set("INCLUDE", join(vars.inc, ";"));
	config.env.set("LIB", join(vars.lib, ";"));

	linker.args ~= [
		"/nologo",
		"/defaultlib:libcmt",
		"/defaultlib:oldnames",
		"legacy_stdio_definitions.lib",
	];
}

fn doToolChainCrossMSVC(drv: Driver, config: Configuration, outside: Environment)
{
	assert(!config.isHost);

	// First see if the linker is specified.
	linker := drv.getCmd(config.isHost, LinkerName);

	// If it was not specified get 'lld-link' from the LLVM toolchain.
	if (linker is null) {
		linker = config.getTool(LLDLinkName);
	}

	// Always add it to the config.
	assert(linker !is null);
	linker = config.addTool(LinkerName, linker.cmd, linker.args);

	// Get the CC setup by the llvm toolchain.
	cc := config.getTool(CCName);
	assert(cc !is null);

	vars: VarsForMSVC;
	getDirsFromEnv(drv, outside, ref vars);
	fillInListsForMSVC(ref vars);

	foreach (i; vars.inc) {
		cc.args ~= "-I" ~ i;
	}

	linker.args ~= [
		"/nologo",
		"/defaultlib:libcmt",
		"/defaultlib:oldnames",
		"legacy_stdio_definitions.lib",
	];

	foreach (l; vars.lib) {
		linker.args ~= format("/LIBPATH:%s", l);
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
	vars.tPath(format("%s/bin/x64", vars.dirWinSDK));
	vars.tPath(format("%s/bin/x86", vars.dirWinSDK));
	vars.tPath(format("%s/VCPackages", vars.dirVC));
	vars.tPath(format("%s/BIN/amd64", vars.dirVC));

	vars.tInc(format("%s/include", vars.dirVC));
	vars.tInc(format("%s/include/%s/ucrt", vars.dirUCRT, vars.numUCRT));
	vars.tInc(format("%s/include/%s/shared", vars.dirWinSDK, vars.numWinSDK));
	vars.tInc(format("%s/include/%s/um", vars.dirWinSDK, vars.numWinSDK));
	vars.tInc(format("%s/include/%s/winrt", vars.dirWinSDK, vars.numWinSDK));

	vars.tLib(format("%s/lib/amd64", vars.dirVC));
	vars.tLib(format("%s/lib/%s/ucrt/x64", vars.dirUCRT, vars.numUCRT));
	vars.tLib(format("%s/lib/%s/um/x64", vars.dirWinSDK, vars.numWinSDK));
}


/*
 *
 * Fill in configuration.
 *
 */

fn fillInConfigCommands(drv: Driver, config: Configuration)
{
	volta := drv.getCmd(config.isHost, VoltaName);
	if (volta !is null) {
		volta.print = VoltaPrint;
	}

	config.linkerCmd = config.getTool(LinkerName);
	config.clangCmd = config.getTool(ClangName);
	config.rdmdCmd = config.getTool(RdmdName);
	config.nasmCmd = config.getTool(NasmName);
	config.ccCmd = config.getTool(CCName);

	assert(config.linkerCmd !is null);
	assert(config.clangCmd !is null);
	assert(config.rdmdCmd !is null);
	assert(config.nasmCmd !is null);
	assert(config.ccCmd !is null);

	config.clangCmd.print = ClangPrint;
	config.rdmdCmd.print = RdmdPrint;
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
