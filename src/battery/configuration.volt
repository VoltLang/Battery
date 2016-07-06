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
	enum Kind
	{
		LD,    // LD
		GCC,   // GCC
		Link,  // MSVC
		Clang, // LLVM Clang
	}

	/// Type of compiler.
	Kind kind;

	/// Fully qualified command.
	string cmd;
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
}

/**
 * Holds information about the rdmd command.
 */
class Rdmd
{
public:
	string rdmd;
	string dmd;
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
	Rdmd rdmd;
	CCompiler cc;

	Arch arch;
	Platform platform;
}
