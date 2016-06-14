// Copyright © 2015-2016, Jakob Bornecrantz.  All rights reserved.
// See copyright notice in src/battery/license.volt (BOOST ver. 1.0).
module battery.policy.host;

import battery.configuration;
import battery.util.path : searchPath;
import battery.policy.volta : getVolta;


version (MSVC) {
	enum VoltaCommand = "volt.exe";

	enum HostCCompilerCommand = "cl.exe";
	enum HostCCompilerFlag = "--cl";
	enum HostCCompilerKind = CCompiler.Kind.CL;

	enum HostLinkerCommand = "link.exe";
	enum HostLinkerFlag = "--link";
	enum HostPlatform = Platform.MSVC;
} else version (Linux) {
	enum VoltaCommand = "volt";

	enum HostCCompilerCommand = "gcc";
	enum HostCCompilerFlag = "--cc";
	enum HostCCompilerKind = CCompiler.Kind.GCC;

	enum HostLinkerCommand = "gcc";
	enum HostLinkerFlag = "--cc";
	enum HostPlatform = Platform.Linux;
} else version (OSX) {
	enum VoltaCommand = "volt";
	enum HostLinkerCommand = "clang";
	enum HostLinkerFlag = "--cc";
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

Configuration getHostConfig(string path)
{
	volta := getVolta(path);
	linker := getHostLinker(path);
	cc := getHostCCompiler(path);

	c := new Configuration();
	c.path = path;
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
	linker.cmd = searchPath(HostLinkerCommand, path);
	linker.flag = HostLinkerFlag;

	return linker;
}

CCompiler getHostCCompiler(string path)
{
	cc := new CCompiler();
	cc.cmd = searchPath(HostCCompilerCommand, path);
	cc.flag = HostCCompilerFlag;
	cc.kind = HostCCompilerKind;

	return cc;
}
