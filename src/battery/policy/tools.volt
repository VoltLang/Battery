// Copyright 2015-2024, Jakob Bornecrantz.
// SPDX-License-Identifier: BSL-1.0
module battery.policy.tools;

import battery.interfaces;
import battery.driver;
import llvmVersion = battery.frontend.llvmVersion;


enum VoltaName = "volta";
enum GdcName = "gdc";
enum LdcName = "ldc";
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
enum WasmLLDName = "wasm-ld";

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
enum WasmLLDCommand = WasmLLDName;

enum VoltaPrint =      "  VOLTA    ";
enum NasmPrint =       "  NASM     ";
enum RdmdPrint =       "  RDMD     ";
enum GdcPrint =        "  GDC      ";
enum LdcPrint =        "  LDC      ";
enum LinkPrint =       "  LINK     ";
enum CLPrint   =       "  CL       ";
enum LLVMConfigPrint = "  LLVM-CONFIG  ";
enum LLVMArPrint =     "  LLVM-AR  ";
enum ClangPrint =      "  CLANG    ";
enum LDLLDPrint =      "  LD.LLD   ";
enum LLDLinkPrint =    "  LLD-LINK ";
enum WasmLLDPrin =     "  WASM-LD  ";

enum HostRdmdPrint =   "  HOSTRDMD ";
enum HostGdcPrint =    "  HOSTGDC  ";

enum BootRdmdPrint =   "  BOOTRDMD ";
enum BootGdcPrint =    "  BOOTGDC  ";
enum BootLdcPrint =    "  BOOTLDC  ";


/*
 *
 * Generic helpers.
 *
 */

fn infoCmd(drv: Driver, c: Configuration, cmd: Command, from: string)
{
	drv.info("\t%scmd %s: '%s' from %s.", c.getCmdPre(), cmd.name, cmd.cmd, from);
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
