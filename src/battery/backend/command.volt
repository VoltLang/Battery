// Copyright 2016-2018, Jakob Bornecrantz.
// SPDX-License-Identifier: BSL-1.0
module battery.backend.command;

import watt.path : dirSeparator, fullPath;
import watt.text.string : endsWith;
import watt.text.format;
import io = watt.io;
import core.c.stdlib : exit;
import battery.interfaces;
import battery.util.path : cleanPath;
import battery.util.printing;
import battery.policy.tools : ClangName, LLVMArName;


struct ArgsGenerator
{
public:
	alias Callback = scope dg(b: Project) string[];

	enum Kind
	{
		VoltaSrc      = 0x001,
		VoltaLink     = 0x002,
		VoltaBc       = 0x004,
		VoltaAr       = 0x008,
		ClangAssemble = 0x010,
		ClangLink     = 0x020,
		LinkLink      = 0x040,
		Dmd           = 0x080,
		Gdc           = 0x100,

		AnyLdLink     = VoltaLink | ClangLink | Gdc,
		AnyLink       = VoltaLink | ClangLink | LinkLink,
		AnyVolta      = VoltaSrc | VoltaLink | VoltaBc | VoltaAr,
		AnyClang      = ClangAssemble | ClangLink,
	}


public:
	config: Configuration;
	libs: Lib[];
	exes: Exe[];
	store: Project[string];
	voltaArgs: string[];
	archStr: string;
	platformStr: string;
	buildDir: string;

	//! The runtime.
	rt: Lib;


public:
	fn setup(config: Configuration, libs: Lib[], exes: Exe[])
	{
		this.config = config;
		this.libs = libs;
		this.exes = exes;
		this.store = [:];

		this.archStr = archToString(config.arch);
		this.platformStr = platformToString(config.platform);

		this.buildDir = ".battery" ~ dirSeparator ~
			this.archStr ~ "-" ~ this.platformStr;

		this.voltaArgs = [
			"--no-stdlib",
			"--platform", platformStr,
			"--arch", archStr,
			config.isRelease ? "--release" : "--debug",
		];

		foreach (lib; libs) {
			store[lib.name] = lib;
			if (lib.isTheRT) {
				rt = lib;
			}
		}

		foreach (exe; exes) {
			store[exe.name] = exe;
		}

		assert(rt !is null);
	}

	/*!
	 * Generates a Volta command line to build a binary.
	 */
	fn genVoltArgs(base: Project, kind: Kind, cb: Callback) string[]
	{
		added: Project[string];
		ret: string[];
		exe := cast(Exe)base;

		// Copy the default command line.
		if (kind & Kind.AnyVolta) {
			ret ~= voltaArgs;
		}

		if (kind & Kind.VoltaBc) {
			ret ~= ["-c", "--emit-llvm"];
		}

		// Should we give Volta the clang command?
		if (kind & Kind.VoltaAr) {
			clang := config.getTool(ClangName);
			assert(clang !is null);

			ret ~= ["--clang", clang.cmd];
			foreach (arg; clang.args) {
				ret ~= ["--Xclang", arg];
			}
		}

		// Should we give Volta the llvm-ar command?
		if (kind & Kind.VoltaAr) {
			ar := config.getTool(LLVMArName);
			assert(ar !is null);

			ret ~= ["--llvm-ar", ar.cmd];
			foreach (arg; ar.args) {
				ret ~= ["--Xllvm-ar", arg];
			}
		}

		// Are we linking with Volta, give it the linker.
		if (kind & Kind.VoltaLink) {
			ret ~= [
				getLinkerFlag(config),
				config.linkerCmd.cmd
			];

			pass := getLinkerPassFlag(config);
			foreach (arg; config.linkerCmd.args) {
				ret ~= [pass, arg];
			}
		}

		fn traverse(b: Project)
		{
			// Has this dep allready been added.
			p := b.name in added;
			if (p !is null) {
				return;
			}

			// Keep track of it now.
			added[b.name] = b;

			if (cb !is null) {
				ret ~= cb(b);
			}

			// Only needed when compiling source.
			if (kind & Kind.VoltaSrc) {

				if (shouldSourceInclude(b)) {
					ret ~= ["--src-I", fullPath(b.srcDir)];
				} else {
					ret ~= ["--lib-I", fullPath(b.srcDir)];
				}

				foreach (def; b.defs) {
					ret ~= ["-D", def];
				}

				foreach (path; b.stringPaths) {
					ret ~= ["-J", path];
				}

				if (b.warningsEnabled) {
					ret ~= "-w";
				}
			}

			if (kind & Kind.Dmd) {
				ret ~= ("-I" ~ b.srcDir);

				foreach (def; b.defs) {
					ret ~= new "-version=${def}";
				}
			}

			if (kind & Kind.Gdc) {
				ret ~= ["-I", b.srcDir];

				foreach (def; b.defs) {
					ret ~= new "-fversion=${def}";
				}
			}

			// Shared with clang and volta.
			if (kind & Kind.AnyLdLink) {
				foreach (path; b.frameworkPaths) {
					ret ~= ["-F", path];
				}

				foreach (framework; b.frameworks) {
					ret ~= ["-framework", framework];
				}

				foreach (path; b.libPaths) {
					ret ~= ["-L", path];
				}

				foreach (l; b.libs) {
					ret ~= ["-l", l];
				}
			}

			if (kind & Kind.Dmd) {
				foreach (path; b.libPaths) {
					ret ~= ("-L-L" ~ path);
				}

				foreach (l; b.libs) {
					version (Windows) {
						ret ~= ("-L" ~ l);
					} else {
						ret ~= ("-L-l" ~ l);
					}
				}

				ret ~= "-g";
			}

			if (kind & Kind.LinkLink) {
				foreach (lib; b.libs) {
					ret ~= lib;
				}

				foreach (path; b.libPaths) {
					ret ~= "/LIBPATH:" ~ path;
				}

				foreach (arg; b.xlink) {
					ret ~= arg;
				}

				foreach (arg; b.xlinker) {
					ret ~= arg;
				}
			}

			if (kind & Kind.ClangLink) {
				foreach (arg; b.xcc) {
					ret ~= arg;
				}

				foreach (arg; b.xlink) {
					ret ~= ["-Xlinker", arg];
				}

				foreach (arg; b.xlinker) {
					ret ~= ["-Xlinker", arg];
				}
			}

			if (kind & Kind.VoltaLink) {
				foreach (arg; b.xcc) {
					ret ~= ["--Xcc", arg];
				}

				foreach (arg; b.xlink) {
					ret ~= ["--Xlink", arg];
				}

				foreach (arg; b.xlinker) {
					ret ~= ["--Xlinker", arg];
				}
			}

			foreach (dep; b.deps) {
				dp := dep in store;
				if (dp is null) {
					io.error.writefln("No dependency '%s' found.", dep);
					exit(-1);
				}
				traverse(*dp);
			}
		}

		traverse(base);

		if (!(kind & Kind.Dmd || kind & Kind.Gdc)) {
			// Implictly add rt as a dependancy
			traverse(rt);
		}

		return ret;
	}

	fn shouldSourceInclude(b: Project) bool
	{
		lib := cast(Lib)b;

		// If this is a exe the source is included in the resulting target.
		if (lib is null) {
			return true;
		}

		// For libraries just don't include the source in the target.
		return false;
	}

	//! Should when we are building generate json files.
	fn shouldJSON(b: Project) string
	{
		if (b.jsonOutput !is null) {
			return b.jsonOutput;
		}
		if (config.shouldJSON) {
			return genVoltJSON(b.name);
		}
		return null;
	}

	fn genVolted() string
	{
		cmd := cleanPath(buildDir ~ dirSeparator ~ "volted");
		version (Windows) {
			if (!endsWith(cmd, ".exe")) {
				cmd ~= ".exe";
			}
		}
		return cmd;
	}

	fn getFileOFromBC(name: string) string
	{
		assert(name.length > 3);
		return name[0 .. $ - 3] ~ ".o";
	}

	fn genFileBC(name: string) string
	{
		return cleanPath(buildDir ~ dirSeparator ~ name ~ ".bc");
	}

	fn genAsmO(name: string) string
	{
		return cleanPath(buildDir ~ dirSeparator ~ name ~ ".o");
	}

	fn genCO(name: string) string
	{
		return cleanPath(buildDir ~ dirSeparator ~ name ~ ".o");
	}

	fn genSO(name: string) string
	{
		ending := config.isLTO ? ".thin.o" : ".o";
		return cleanPath(buildDir ~ dirSeparator ~ name ~ ending);
	}

	fn genVoltO(name: string) string
	{
		ending := config.isLTO ? ".thin.o" : ".o";
		return cleanPath(buildDir ~ dirSeparator ~ name ~ ending);
	}

	fn genVoltA(name: string) string
	{
		ending := config.isLTO ? ".thin.a" : ".a";
		return cleanPath(buildDir ~ dirSeparator ~ name ~ ending);
	}

	fn genVoltBc(name: string) string
	{
		return cleanPath(buildDir ~ dirSeparator ~ name ~ ".bc");
	}

	fn genVoltDep(name: string) string
	{
		return cleanPath(buildDir ~ dirSeparator ~ name ~ ".d");
	}

	fn genVoltJSON(name: string) string
	{
		return cleanPath(buildDir ~ dirSeparator ~ name ~ ".json");
	}


private:
	fn getLinkerFlag(config: Configuration) string
	{
		final switch (config.linkerKind) with (LinkerKind) {
		case Link: return "--link";
		case Clang: return "--cc";
		case Invalid: assert(false);
		}
	}

	fn getLinkerPassFlag(config: Configuration) string
	{
		final switch (config.linkerKind) with (LinkerKind) {
		case Link: return "--Xlink";
		case Clang: return "--Xcc";
		case Invalid: assert(false);
		}
	}
}
