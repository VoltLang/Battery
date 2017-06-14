// Copyright © 2016, Jakob Bornecrantz.  All rights reserved.
// See copyright notice in src/battery/license.volt (BOOST ver. 1.0).
module battery.backend.command;

import watt.path : dirSeparator;
import watt.text.string : endsWith;
import io = watt.io;
import core.c.stdlib : exit;
import battery.interfaces;
import battery.configuration;
import battery.util.path : cleanPath;
import battery.policy.tools : ClangName, LLVMArName;


struct ArgsGenerator
{
public:
	alias Callback = scope dg(b: Base) string[];

	enum Kind
	{
		VoltaSrc      = 0x01,
		VoltaLink     = 0x02,
		VoltaBc       = 0x04,
		VoltaAr       = 0x08,
		ClangAssemble = 0x10,
		ClangLink     = 0x20,
		LinkLink      = 0x40,

		AnyLdLink     = VoltaLink | ClangLink,
		AnyLink       = VoltaLink | ClangLink | LinkLink,
		AnyVolta      = VoltaSrc | VoltaLink | VoltaBc | VoltaAr,
		AnyClang      = ClangAssemble | ClangLink,
	}


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
			config.isRelease ? "--release" : "--debug",
		];

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
	fn genVoltArgs(base: Base, kind: Kind, cb: Callback) string[]
	{
		added: Base[string];
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

		fn traverse(b: Base)
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
					ret ~= ["--src-I", b.srcDir];
				} else {
					ret ~= ["--lib-I", b.srcDir];
				}

				foreach (def; b.defs) {
					ret ~= ["-D", def];
				}

				foreach (path; b.stringPaths) {
					ret ~= ["-J", path];
				}
			}

			// Shared with clang and volta.
			if (kind & Kind.AnyLdLink) {
				foreach (path; b.frameworkPaths) {
					ret ~= ["-F", path];
				}

				foreach (framework; b.frameworks) {
					ret ~= ["--framework", framework];
				}

				foreach (path; b.libPaths) {
					ret ~= ["-L", path];
				}

				foreach (l; b.libs) {
					ret ~= ["-l", l];
				}
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

		// Implictly add rt as a dependancy
		traverse(store["rt"]);

		return ret;
	}

	fn shouldSourceInclude(b: Base) bool
	{
		lib := cast(Lib)b;

		// If this is a exe the source is included in the resulting target.
		if (lib is null) {
			return true;
		}

		// For libraries just don't include the source in the target.
		return false;
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

	fn genFileO(name: string) string
	{
		return cleanPath(buildDir ~ dirSeparator ~ name ~ ".o");
	}

	fn genVoltO(name: string) string
	{
		return cleanPath(buildDir ~ dirSeparator ~ name ~ ".o");
	}

	fn genVoltA(name: string) string
	{
		return cleanPath(buildDir ~ dirSeparator ~ name ~ ".a");
	}

	fn genVoltBc(name: string) string
	{
		return cleanPath(buildDir ~ dirSeparator ~ name ~ ".bc");
	}

	fn genVoltDep(name: string) string
	{
		return cleanPath(buildDir ~ dirSeparator ~ name ~ ".d");
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
