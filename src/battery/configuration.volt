// Copyright © 2016, Jakob Bornecrantz.  All rights reserved.
// See copyright notice in src/battery/license.volt (BOOST ver. 1.0).
module battery.configuration;

import watt.process : Environment;
public import battery.defines;


/**
 * Holds information about the Volta compiler and runtime.
 */
class Volta
{
	string cmd;

	string rtBin;
	string rtDir;

	string[][4] rtLibs;
}

/**
 * Holds information about linker.
 */
class Linker
{
	/// Fully qualified command.
	string cmd;

	/// How to give the cmd to Volta, --link, --cc, --ld.
	string flag;
}

/**
 * Holds information about the C compiler.
 */
class CCompiler
{
public:
	enum Kind
	{
		CL,    // MSVC
		GCC,   // GCC
		Clang, // LLVM Clang
	}

	/// Type of compiler.
	Kind kind;

	/// Fully qualified command.
	string cmd;

	/// How to give the cmd to Volta, --cc.
	string flag;
}

/**
 * A build configuration for one or more builds.
 *
 * This can be shared between multiple builds. When cross-compiling there will
 * be multiple configurations, one for the target and another for the host.
 */
class Configuration
{
public:
	Environment env;

	Volta volta;
	Linker linker;
	CCompiler cc;

	Arch arch;
	Platform platform;

	string[] defs;

	string buildDir;

	uint hash;

	bool isDebug;


public:
	string buildDirDerived;
}
