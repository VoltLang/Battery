// Copyright 2016-2018, Jakob Bornecrantz.
// SPDX-License-Identifier: BSL-1.0
/*!
 * Common enums and classes, aka "defines".
 */
module battery.defines;


/*!
 * Each of these listed platforms corresponds
 * to a Version identifier.
 *
 * Posix and Windows are not listed here as they
 * they are available on multiple platforms.
 *
 * Posix on Linux and OSX.
 * Windows on MinGW and MSVC.
 */
enum Platform
{
	MSVC,  //!< Windows and MSVC compatible.
	Linux, //!< Linux.
	OSX,   //!< Apple OSX
	Metal, //!< Bare Metal
}

/*!
 * Each of these listed architectures corresponds to a Version identifier.
 */
enum Arch
{
	X86,     //!< X86 32 Bit
	X86_64,  //!< X86 64 Bit aka AMD64.
	AArch64, //!< AArch64, ARM64.
}

/*!
 * What kind of linker is being used, selects arguments.
 */
enum LinkerKind
{
	Invalid, //!< Internal error state.
	Link,    //!< MSVC
	Clang,   //!< LLVM Clang
}

/*!
 * What kind of C-compiler is being used, selects arguments.
 */
enum CCKind
{
	Invalid, //!< Internal error state.
	Clang,   //!< LLVM Clang
}

/*!
 * Tracking if a configuration is native, host or cross-compile.
 */
enum ConfigKind
{
	Invalid,   //!< Internal error state.
	Bootstrap, //!< For boostraping the volted binary.
	Native,    //!< Target is the same as the host system.
	Host,      //!< For cross-compile, this config is the host system.
	Cross,     //!< For cross-compile, this is the target config.
}

/*!
 * Represents a single command that can be launched.
 */
class Command
{
public:
	name: string;   //!< Textual name.
	cmd: string;    //!< Name and path.
	args: string[]; //!< Extra args to give when invoking.
	print: string;  //!< Name to print.


public:
	this() { }

	this(cmd: string, args: string[])
	{
		this.cmd = cmd;
		this.args = args;
	}

	this(name: string, c: Command)
	{
		this.name = name;
		this.cmd = c.cmd;
		this.print = c.print;
		this.args = new string[](c.args);
	}
}

/*!
 * A struct holding information from a battery.conf.toml file.
 */
struct BatteryConfig
{
	filename: string;

	voltaCmd: string;
	nasmCmd: string;

	gdcCmd: string;
	rdmdCmd: string;

	pkgs: string[];

	llvmConfigCmd: string;
	llvmArCmd: string;
	llvmClangCmd: string;
	llvmLinkCmd: string;
	llvmWasmCmd: string;
	llvmC: string;
}
