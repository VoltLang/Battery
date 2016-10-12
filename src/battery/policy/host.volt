// Copyright © 2015-2016, Jakob Bornecrantz.  All rights reserved.
// See copyright notice in src/battery/license.volt (BOOST ver. 1.0).
module battery.policy.host;

import watt.process : retriveEnvironment, Environment, searchPath;
import battery.interfaces;
import battery.configuration;
import battery.policy.programs;

version (MSVC) {
	enum HostPlatform = Platform.MSVC;

	enum HostCCompilerCommand = "cl.exe";
	enum HostCCompilerKind = CCKind.CL;

	enum HostLinkerCommand = "link.exe";
	enum HostLinkerKind = LinkerKind.Link;

	enum RdmdCommand = "rdmd.exe";
	enum DmdCommand = "dmd.exe";

	enum NasmCommand = "nasm.exe";
} else version (Linux) {
	enum HostPlatform = Platform.Linux;

	enum HostCCompilerCommand = "gcc";
	enum HostCCompilerKind = CCKind.GCC;

	enum HostLinkerCommand = "gcc";
	enum HostLinkerKind = LinkerKind.GCC;

	enum RdmdCommand = "rdmd";
	enum DmdCommand = "dmd";

	enum NasmCommand = "nasm";
} else version (OSX) {
	enum HostPlatform = Platform.OSX;

	enum HostCCompilerCommand = "clang";
	enum HostCCompilerKind = CCKind.GCC;

	enum HostLinkerCommand = "clang";
	enum HostLinkerKind = LinkerKind.Clang;

	enum RdmdCommand = "rdmd.exe";
	enum DmdCommand = "dmd.exe";

	enum NasmCommand = "nasm";
} else {
	static assert(false, "native platform not supported");
}

version (X86_64) {
	enum Arch HostArch = Arch.X86_64;
} else version (X86) {
	enum Arch HostArch = Arch.X86;
} else {
	static assert(false, "native arch not supported");
}

fn getHostConfig(drv: Driver) Configuration
{
	outside := retriveEnvironment();
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

		// Only needed for RDMD if it isn't installed properly.
		//env.set("VCINSTALLDIR", outside.getOrNull("VCINSTALLDIR"));
		//env.set("WindowsSdkDir", outside.getOrNull("WindowsSdkDir"));
		//env.set("UniversalCRTSdkDir", outside.getOrNull("UniversalCRTSdkDir"));
		//env.set("UCRTVersion", outside.getOrNull("UCRTVersion"));
	}

	c := new Configuration();
	c.env = env;
	c.arch = HostArch;
	c.platform = HostPlatform;
	c.setupHostCCompiler(path);
	c.setupHostLinker(path);
	c.setupHostRdmd(path);

	drv.setupNasm(c, c);

	return c;
}

fn setupHostCCompiler(config: Configuration, path: string)
{
	config.ccKind = HostCCompilerKind;
	config.ccCmd = makeCommand(HostCCompilerCommand, path);
}

fn setupHostLinker(config: Configuration, path: string)
{
	// Can we reuse the ccompiler as linker.
	final switch (config.ccKind) with (CCKind) {
	case Clang:
		config.linkerKind = LinkerKind.Clang;
		config.linkerCmd = config.ccCmd;
		return;
	case GCC:
		config.linkerKind = LinkerKind.GCC;
		config.linkerCmd = config.ccCmd;
		return;
	case CL, Invalid: break;
	}

	config.linkerKind = HostLinkerKind;
	config.linkerCmd = makeCommand(HostLinkerCommand, path);
}

fn setupHostNasm(config: Configuration, path: string)
{
	config.nasmCmd = makeCommand(NasmCommand, path);
}

fn setupHostRdmd(config: Configuration, path: string)
{
	config.rdmdCmd = makeCommand(RdmdCommand, path);
}


private:
/**
 * Search the command path and make a Command instance.
 */
fn makeCommand(name: string, path: string) Command
{
	cmd := searchPath(name, path);
	if (cmd is null) {
		return null;
	}

	c := new Command();
	c.cmd = cmd;
	c.name = name;
	return c;
}
