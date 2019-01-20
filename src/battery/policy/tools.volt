// Copyright 2015-2018, Jakob Bornecrantz.
// SPDX-License-Identifier: BSL-1.0
module battery.policy.tools;

import watt.text.format : format;
import watt.text.string : split, startsWith, endsWith;
import watt.path : pathSeparator, dirSeparator, exists;
import watt.process : retriveEnvironment, Environment;
import battery.commonInterfaces;
import battery.configuration;
import battery.driver;
import battery.util.path : searchPath;
import llvmVersion = battery.frontend.llvmVersion;

import nasm = battery.detect.nasm;


enum VoltaName = "volta";
enum GdcName = "gdc";
enum NasmName = "nasm";
enum RdmdName = "rdmd";
enum CLName = "cl";
enum LinkName = "link";
enum CCName = "ccompiler";
enum LinkerName = "linker";
enum LLVMConfigName = "llvm-config";
enum LLVMArName = "llvm-ar";
enum ClangName = "clang";
enum LDLLDName = "ld.lld";
enum LLDLinkName = "lld-link";

enum NasmCommand = NasmName;
enum RdmdCommand = RdmdName;
enum GdcCommand = GdcName;
enum CLCommand = "cl.exe";
enum LinkCommand = "link.exe";
enum LLVMConfigCommand = LLVMConfigName;
enum LLVMArCommand = LLVMArName;
enum ClangCommand = ClangName;
enum LDLLDCommand = LDLLDName;
enum LLDLinkCommand = LLDLinkName;

enum VoltaPrint =      "  VOLTA    ";
enum NasmPrint =       "  NASM     ";
enum RdmdPrint =       "  RDMD     ";
enum GdcPrint =        "  GDC      ";
enum LinkPrint =       "  LINK     ";
enum CLPrint   =       "  CL       ";
enum LLVMConfigPrint = "  LLVM-CONFIG  ";
enum LLVMArPrint =     "  LLVM-AR  ";
enum ClangPrint =      "  CLANG    ";
enum LDLLDPrint =      "  LD.LLD   ";
enum LLDLinkPrint =    "  LLD-LINK ";

enum HostRdmdPrint =   "  HOSTRDMD ";
enum HostGdcName =     "  HOSTGDC  ";


fn infoCmd(drv: Driver, c: Configuration, cmd: Command, from: string)
{
	drv.info("\t%scmd %s: '%s' from %s.", c.getCmdPre(), cmd.name, cmd.cmd, from);
}

fn infoCmd(drv: Driver, c: Configuration, cmd: Command, given: bool = false)
{
	if (given) {
		drv.info("\t%scmd %s: '%s' from arguments.", c.getCmdPre(), cmd.name, cmd.cmd);
	} else {
		drv.info("\t%scmd %s: '%s' from path.", c.getCmdPre(), cmd.name, cmd.cmd);
	}
}

/*!
 * Ensures that a command/tool is there.
 * Will fill in arguments if it knows how to.
 */
fn fillInCommand(drv: Driver, c: Configuration, name: string) Command
{
	switch (name) {
	case NasmName: return handleNASM(drv, c);
	default: break;
	}

	cmd := drv.getCmd(c.isBootstrap, name);
	if (cmd is null) {
		switch (name) {
		case ClangName: cmd = getClang(drv, c, name); break;
		case RdmdName:  cmd = getRdmd(drv, c, name); break;
		case GdcName:   cmd = getGdc(drv, c, name); break;
		case LinkName:  cmd = getLink(drv, c, name); break;
		case NasmName: assert(false);
		default: assert(false);
		}

		if (cmd is null) {
			drv.abort("could not find the %scommand '%s'", c.getCmdPre(), name);
		}
	} else {
		drv.infoCmd(c, cmd, true);
	}

	switch (name) {
	case ClangName: addClangArgs(drv, c, cmd); break;
	case RdmdName:  addRdmdArgs(drv, c, cmd); break;
	case GdcName:   addRdmdArgs(drv, c, cmd); break;
	case LinkName: break;
	case NasmName: assert(false);
	default: assert(false);
	}

	return cmd;
}

/*!
 * Transitional function to new detect code.
 */
fn handleNASM(drv: Driver, c: Configuration) Command
{
	res: nasm.Result;
	arg: nasm.Argument;
	arg.arch = c.arch;
	arg.platform = c.platform;
	arg.path = c.env.getOrNull("PATH");

	cmd := drv.getCmd(c.isBootstrap, NasmName);
	if (cmd !is null) {
		arg.argCmd = cmd.cmd;
		arg.argArgs = cmd.args;
	} else {
		cmd = new Command();
	}

	if (!nasm.detect(ref arg, out res)) {
		drv.abort("Failed to find nasm!");
	}

	cmd.cmd = res.cmd;
	cmd.args = res.args;
	cmd.name = NasmName;
	cmd.print = NasmPrint;
	return cmd;
}

/*
 *
 * Clang functions.
 *
 */

fn getClang(drv: Driver, config: Configuration, name: string) Command
{
	return drv.makeCommand(config, name, ClangCommand, ClangPrint);
}

fn addClangArgs(drv: Driver, config: Configuration, c: Command)
{
	c.args ~= ["-target", config.getLLVMTargetString()];
}

//! configs used with LLVM tools, Clang and Volta.
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
		case X86: return "i386-apple-macosx10.9.0";
		case X86_64: return "x86_64-apple-macosx10.9.0";
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
 * MSVC functions.
 *
 */

fn getCL(drv: Driver, config: Configuration, name: string) Command
{
	return drv.makeCommand(config, name, CLCommand, CLPrint);
}

fn getLink(drv: Driver, config: Configuration, name: string) Command
{
	return drv.makeCommand(config, name, LinkCommand, LinkPrint);
}

fn getLLDLink(drv: Driver, config: Configuration, name: string) Command
{
	return drv.makeCommand(config, name, LLDLinkCommand, LLDLinkPrint);
}


/*
 *
 * Rdmd functions.
 *
 */

fn getRdmd(drv: Driver, config: Configuration, name: string) Command
{
	return drv.makeCommand(config, name, RdmdCommand, RdmdPrint);
}

fn addRdmdArgs(drv: Driver, config: Configuration, c: Command)
{
	final switch (config.arch) with (Arch) {
	case X86: c.args ~= "-m32"; break;
	case X86_64: c.args ~= "-m64"; break;
	}
}

fn addLlvmVersionsToBootstrapCompiler(drv: Driver, config: Configuration, c: Command)
{
	fn getVersionFlag(s: string) string
	{
		if (c.name == "rdmd") {
			return new "-version=${s}";
		} else if (c.name == "gdc") {
			return new "-fversion=${s}";
		} else {
			assert(false, "unknown bootstrap compiler");
		}
	}

	assert(config.llvmVersion !is null);
	llvmVersions := llvmVersion.identifiers(config.llvmVersion);
	foreach (v; llvmVersions) {
		c.args ~= getVersionFlag(v);
	}
}


/*
 *
 * GDC functions.
 *
 */

fn getGdc(drv: Driver, config: Configuration, name: string) Command
{
	return drv.makeCommand(config, name, GdcCommand, GdcPrint);
}

fn addGdcArgs(drv: Driver, config: Configuration, c: Command)
{
	final switch (config.arch) with (Arch) {
	case X86: c.args ~= "-m32"; break;
	case X86_64: c.args ~= "-m64"; break;
	}

	assert(config.llvmVersion !is null);
	llvmVersions := llvmVersion.identifiers(config.llvmVersion);
	foreach (v; llvmVersions) {
		c.args ~= format("-fversion=%s", v);
	}
}


/*
 *
 * Generic helpers.
 *
 */

fn getShortName(name: string) string
{
	if (startsWith(name, "host-")) {
		return name[5 .. $];
	}
	return name;
}

private:
//! Search the command path and make a Command instance.
fn makeCommand(drv: Driver, config: Configuration, name: string, cmd: string,
               print: string) Command
{
	cmd = searchPath(cmd, config.env.getOrNull("PATH"));
	if (cmd is null) {
		return null;
	}

	c := new Command();
	c.cmd = cmd;
	c.name = name;
	c.print = print;

	drv.infoCmd(config, c);

	return c;
}

fn getCmdPre(c: Configuration) string
{
	final switch (c.kind) with (ConfigKind) {
	case Invalid: return "invalid ";
	case Native: return "";
	case Host: return "host ";
	case Cross: return "cross ";
	case Bootstrap: return "boot ";
	}
}
