// Copyright © 2015-2016, Jakob Bornecrantz.  All rights reserved.
// See copyright notice in src/battery/license.volt (BOOST ver. 1.0).
module battery.policy.host;

import watt.process : retriveEnvironment, Environment;
import battery.configuration;
import battery.util.path : searchPath;
import battery.policy.volta : getVolta;


version (MSVC) {
	enum VoltaCommand = "volt.exe";

	enum HostCCompilerCommand = "cl.exe";
	enum HostCCompilerKind = CCompiler.Kind.CL;

	enum HostLinkerCommand = "link.exe";
	enum HostLinkerKind = Linker.Kind.Link;
	enum HostPlatform = Platform.MSVC;
} else version (Linux) {
	enum VoltaCommand = "volt";

	enum HostCCompilerCommand = "gcc";
	enum HostCCompilerKind = CCompiler.Kind.GCC;

	enum HostLinkerCommand = "gcc";
	enum HostLinkerKind = Linker.Kind.GCC;
	enum HostPlatform = Platform.Linux;
} else version (OSX) {
	enum VoltaCommand = "volt";

	enum HostCCompilerCommand = "clang";
	enum HostCCompilerKind = CCompiler.Kind.GCC;

	enum HostLinkerCommand = "clang";
	enum HostLinkerKind = Linker.Kind.Clang;
	enum HostPlatform = Platform.OSX;
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

	c := new Configuration();
	c.env = env;
	c.volta = volta;
	c.linker = linker;
	c.cc = cc;
	c.arch = HostArch;
	c.platform = HostPlatform;

	return c;
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
