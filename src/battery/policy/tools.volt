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
enum HostGdcPrint =    "  HOSTGDC  ";

enum BootRdmdPrint =   "  BOOTRDMD ";
enum BootGdcPrint =    "  BOOTGDC  ";


/*
 *
 * Generic helpers.
 *
 */

fn infoCmd(drv: Driver, c: Configuration, cmd: Command, from: string)
{
	drv.info("\t%scmd %s: '%s' from %s.", c.getCmdPre(), cmd.name, cmd.cmd, from);
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
