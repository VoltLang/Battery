// Copyright © 2016, Jakob Bornecrantz.  All rights reserved.
// See copyright notice in src/battery/license.volt (BOOST ver. 1.0).
module battery.backend.command;

import watt.path : dirSeparator;
import battery.interfaces;
import battery.configuration;


struct ArgsGenerator
{
public:
	config: Configuration;
	libs: Lib[];
	exes: Exe[];
	store: Base[string];
	voltaArgs: string[];
	archStr: string;
	platformStr: string;
	buildDir: string;


public:
	fn setup(config: Configuration, libs: Lib[], exes: Exe[])
	{
		this.config = config;
		this.libs = libs;
		this.exes = exes;
		this.store = [];

		this.archStr = .toString(config.arch);
		this.platformStr = .toString(config.platform);

		this.buildDir = ".bin" ~ dirSeparator ~
			this.archStr ~ "-" ~ this.platformStr;

		this.voltaArgs = [
			"--no-stdlib",
			"--platform", platformStr,
			"--arch", archStr,
			getLinkerFlag(config),
			config.linkerCmd.cmd,
		];

		pass := getLinkerPassFlag(config);
		foreach (arg; config.linkerCmd.args) {
			voltaArgs ~= [pass, arg];
		}

		foreach (lib; libs) {
			store[lib.name] = lib;
		}

		foreach (exe; exes) {
			store[exe.name] = exe;
		}
	}

	/**
	 * Generates a Volta command line to build a binary.
	 */
	fn genVoltaArgs(base: Base) string[]
	{
		added: Base[string];
		exe := cast(Exe)base;

		// Copy the default command line.
		ret := voltaArgs;

		fn traverse(b: Base)
		{
			// Has this dep allready been added.
			p := b.name in added;
			if (p !is null) {
				return;
			}

			// Keep track of it now.
			added[b.name] = b;

			lib := cast(Lib)b;

			if (lib !is null) {
				ret ~= ["--lib-I", b.srcDir];
			} else {
				ret ~= ["--src-I", b.srcDir];
			}

			foreach (path; b.libPaths) {
				ret ~= ["-L", path];
			}

			foreach (path; b.stringPaths) {
				ret ~= ["-J", path];
			}

			foreach (l; b.libs) {
				ret ~= ["-l", l];
			}

			foreach (def; b.defs) {
				ret ~= ["-D", def];
			}

			foreach (arg; b.xcc) {
				ret ~= ["--Xcc", arg];
			}

			foreach (arg; b.xlink) {
				ret ~= ["--Xlink", arg];
			}

			foreach (arg; b.xlinker) {
				ret ~= ["--Xlinker", arg];
			}

			foreach (dep; b.deps) {
				traverse(store[dep]);
			}
		}

		traverse(base);

		// Implictly add rt as a dependancy
		traverse(store["rt"]);

		// Set debug.
		if (exe !is null && exe.isDebug) {
			ret ~= "-d";
		}

		return ret;
	}

	fn genNasmArgs() string[]
	{
		bin: string;

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

		return ["-f", bin];
	}

private:
	fn getLinkerFlag(config: Configuration) string
	{
		final switch (config.linkerKind) with (LinkerKind) {
		case LD: return "--ld";
		case GCC: return "--cc";
		case Link: return "--link";
		case Clang: return "--cc";
		case Invalid: assert(false);
		}
	}

	fn getLinkerPassFlag(config: Configuration) string
	{
		final switch (config.linkerKind) with (LinkerKind) {
		case LD: return "--Xld";
		case GCC: return "--Xcc";
		case Link: return "--Xlink";
		case Clang: return "--Xcc";
		case Invalid: assert(false);
		}
	}
}
import watt.io;