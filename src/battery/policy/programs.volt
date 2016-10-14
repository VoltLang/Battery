// Copyright © 2015-2016, Jakob Bornecrantz.  All rights reserved.
// See copyright notice in src/battery/license.volt (BOOST ver. 1.0).
module battery.policy.programs;

import watt.text.format : format, endsWith;
import watt.text.string : split;
import watt.path : pathSeparator, dirSeparator, exists;
import watt.process : retriveEnvironment, Environment;
import battery.interfaces;
import battery.configuration;


enum NasmCommand = "nasm";
enum ClangCommand = "clang";
enum RdmdCommand = "rdmd";
enum LinkCommand = "link.exe";
enum CLCommand = "cl.exe";

enum VoltaPrint = "  VOLTA    ";
enum ClangPrint = "  CLANG    ";
enum NasmPrint =  "  NASM     ";
enum RdmdPrint =  "  RDMD     ";
enum LinkPrint =  "  LINK     ";
enum CLPrint   =  "  CL       ";


/*
 *
 * Clang functions.
 *
 */

fn getClang(drv: Driver, config: Configuration) Command
{
	return drv.makeCommand(ClangCommand, ClangPrint, config.env);
}

fn addClangArgs(drv: Driver, config: Configuration, c: Command)
{
	c.args ~= ["-target", config.getLLVMTargetString()];
}

/// configs used with LLVM tools, Clang and Volta.
fn getLLVMTargetString(config: Configuration) string
{
	final switch (config.platform) with (Platform) {
	case MSVC:
		final switch (config.arch) with (Arch) {
		case X86: return null;
		case X86_64: return "x86_64-pc-windows-msvc";
		}
	case OSX:
		final switch (config.arch) with (Arch) {
		case X86: return "i386-apple-macosx10.7.0";
		case X86_64: return "x86_64-apple-macosx10.7.0";
		}
	case Linux:
		final switch (config.arch) with (Arch) {
		case X86: return "i386-pc-linux-gnu";
		case X86_64: return "x86_64-pc-linux-gnu";
		}
	case Metal:
		final switch (config.arch) with (Arch) {
		case X86: return "i686-pc-none-elf";
		case X86_64: return "x86_64-pc-none-elf";
		}
	}
}


/*
 *
 * Nasm functions.
 *
 */

fn getNasm(drv: Driver, config: Configuration) Command
{
	return drv.makeCommand(NasmCommand, NasmPrint, config.env);
}

fn addNasmArgs(drv: Driver, config: Configuration, c: Command)
{
	c.args ~= ["-f", config.getNasmFormatString()];
}

/// Returns the format to be outputed for this configuration.
fn getNasmFormatString(config: Configuration) string
{
	final switch (config.platform) with (Platform) {
	case MSVC:
		final switch (config.arch) with (Arch) {
		case X86: return "win32";
		case X86_64: return "win64";
		}
	case OSX:
		final switch (config.arch) with (Arch) {
		case X86: return "mach32";
		case X86_64: return "mach64";
		}
	case Linux:
		final switch (config.arch) with (Arch) {
		case X86: return "elf32";
		case X86_64: return "elf64";
		}
	case Metal:
		final switch (config.arch) with (Arch) {
		case X86: return "elf32";
		case X86_64: return "elf64";
		}
	}
}


/*
 *
 * MSVC functions.
 *
 */

fn getCL(drv: Driver, config: Configuration) Command
{
	return drv.makeCommand(CLCommand, CLPrint, config.env);
}

fn getLink(drv: Driver, config: Configuration) Command
{
	return drv.makeCommand(LinkCommand, LinkPrint, config.env);
}


/*
 *
 * Rdmd functions.
 *
 */

fn getRdmd(drv: Driver, config: Configuration) Command
{
	return drv.makeCommand(RdmdCommand, RdmdPrint, config.env);
}

fn addRdmdArgs(drv: Driver, config: Configuration, c: Command)
{
	final switch (config.arch) with (Arch) {
	case X86: c.args ~= "-m32"; break;
	case X86_64: c.args ~= "-m64"; break;
	}
}


/*
 *
 * Generic helpers.
 *
 */

private:
/// Search the command path and make a Command instance.
fn makeCommand(drv: Driver, name: string,
               print: string, env: Environment) Command
{
	cmd := searchPath(name, env);
	if (cmd is null) {
		return null;
	}

	c := new Command();
	c.cmd = cmd;
	c.name = name;
	c.print = print;
	return c;
}

fn searchPath(cmd: string, env: Environment) string
{
	path := env.getOrNull("PATH");
	assert(path !is null);
	assert(pathSeparator.length == 1);

	fmt := "%s%s%s";
	version (Windows) if (!endsWith(cmd, ".exe")) {
		fmt = "%s%s%s.exe";
	}

	foreach (p; split(path, pathSeparator[0])) {
		t := format(fmt, p, dirSeparator, cmd);
		if (exists(t)) {
			return t;
		}
	}

	return null;
}
