// Copyright © 2015-2016, Jakob Bornecrantz.  All rights reserved.
// See copyright notice in src/battery/license.volt (BOOST ver. 1.0).
module battery.policy.programs;

import watt.process : retriveEnvironment, Environment, searchPath;
import battery.interfaces;
import battery.configuration;


version (Windows) {
	enum NasmCommand = "nasm.exe";
} else {
	enum NasmCommand = "nasm";
}

enum NasmPrint = "  NASM     ";

fn setupNasm(drv: Driver, host: Configuration, config: Configuration)
{
	c := new Command();
	c.cmd = searchPath(NasmCommand, config.env.getOrNull("PATH"));

	bin : string;
	final switch (config.platform) with (Platform) {
	case MSVC:
		final switch (config.arch) with (Arch) {
		case X86: bin = "win32"; break;
		case X86_64: bin = "win64"; break;
		}
		break;
	case OSX:
		final switch (config.arch) with (Arch) {
		case X86: bin = "mach32"; break;
		case X86_64: bin = "mach64"; break;
		}
		break;
	case Linux:
		final switch (config.arch) with (Arch) {
		case X86: bin = "elf32"; break;
		case X86_64: bin = "elf64"; break;
		}
		break;
	case Metal:
		final switch (config.arch) with (Arch) {
		case X86: bin = "elf32"; break;
		case X86_64: bin = "elf64"; break;
		}
		break;
	}
	c.args = ["-f", bin];
	c.print = NasmPrint;

	config.nasmCmd = c;
}
