// Copyright © 2015-2016, Jakob Bornecrantz.  All rights reserved.
// See copyright notice in src/battery/license.volt (BOOST ver. 1.0).
module battery.policy.host;

import watt.process : retriveEnvironment, Environment, searchPath;
import battery.configuration;


version (MSVC) {
	enum HostPlatform = Platform.MSVC;

	enum VoltaCommand = "volt.exe";

	enum HostCCompilerCommand = "cl.exe";
	enum HostCCompilerKind = CCompiler.Kind.CL;

	enum HostLinkerCommand = "link.exe";
	enum HostLinkerKind = Linker.Kind.Link;

	enum RdmdCommand = "rdmd";
	enum DmdCommand = "dmd";
} else version (Linux) {
	enum HostPlatform = Platform.Linux;

	enum VoltaCommand = "volt";

	enum HostCCompilerCommand = "gcc";
	enum HostCCompilerKind = CCompiler.Kind.GCC;

	enum HostLinkerCommand = "gcc";
	enum HostLinkerKind = Linker.Kind.GCC;

	enum RdmdCommand = "rdmd";
	enum DmdCommand = "dmd";
} else version (OSX) {
	enum HostPlatform = Platform.OSX;

	enum VoltaCommand = "volt";

	enum HostCCompilerCommand = "clang";
	enum HostCCompilerKind = CCompiler.Kind.GCC;

	enum HostLinkerCommand = "clang";
	enum HostLinkerKind = Linker.Kind.Clang;

	enum RdmdCommand = "rdmd.exe";
	enum DmdCommand = "dmd.exe";
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

Configuration getHostConfig()
{
	outside := retriveEnvironment();
	path := outside.getOrNull("PATH");

	env := new Environment();
	env.set("PATH", path);

	volta := getVolta(path);
	linker := getHostLinker(path);
	cc := getHostCCompiler(path);
	rdmd := getRdmd(path);

	c := new Configuration();
	c.env = env;
	c.volta = volta;
	c.linker = linker;
	c.cc = cc;
	c.rdmd = rdmd;
	c.arch = HostArch;
	c.platform = HostPlatform;

	return c;
}

Volta getVolta(string path)
{
	volta := new Volta();
	volta.cmd = searchPath(VoltaCommand, path);
	volta.rtBin = "%@execdir%/rt/libvrt-%@arch%-%@platform%.o";
	volta.rtDir = "%@execdir%/rt/src";
	volta.rtLibs[Platform.Linux] = ["gc", "dl", "rt"];
	volta.rtLibs[Platform.MSVC] = ["advapi32.lib"];
	volta.rtLibs[Platform.OSX] = ["gc"];

	return volta;
}

Linker getHostLinker(string path)
{
	linker := new Linker();
	linker.kind = HostLinkerKind;
	linker.cmd = searchPath(HostLinkerCommand, path);

	return linker;
}

CCompiler getHostCCompiler(string path)
{
	cc := new CCompiler();
	cc.kind = HostCCompilerKind;
	cc.cmd = searchPath(HostCCompilerCommand, path);

	return cc;
}

Rdmd getRdmd(string path)
{
	rdmd := new Rdmd();
	rdmd.rdmd = searchPath(RdmdCommand, path);
	rdmd.dmd = searchPath(DmdCommand, path);
	return rdmd;
}
