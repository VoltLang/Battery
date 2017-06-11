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


struct ArgsGenerator
{
public:
	alias Callback = scope dg(b: Base) string[];

	enum Kind
	{
		VoltaSrc      = 0x01,
		VoltaLink     = 0x02,
		ClangAssemble = 0x04,
		ClangLink     = 0x08,
		LinkLink      = 0x10,

		AnyLdLink     = VoltaLink | ClangLink,
		AnyLink       = VoltaLink | ClangLink | LinkLink,
		AnyVolta      = VoltaSrc | VoltaLink,
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
	fn genVoltArgs(base: Base, kind: Kind, cb: Callback) string[]
	{
		added: Base[string];
		ret: string[];
		exe := cast(Exe)base;

		// Copy the default command line.
		if (kind & Kind.AnyVolta) {
			ret ~= voltaArgs;
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
				lib := cast(Lib)b;

				if (lib !is null) {
					ret ~= ["--lib-I", b.srcDir];
				} else {
					ret ~= ["--src-I", b.srcDir];
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

	fn genVoltLibraryO(name: string) string
	{
		return cleanPath(buildDir ~ dirSeparator ~ name ~ ".o");
	}

	fn genVoltLibraryBc(name: string) string
	{
		return cleanPath(buildDir ~ dirSeparator ~ name ~ ".bc");
	}

	fn genVoltExeO(name: string) string
	{
		return cleanPath(buildDir ~ dirSeparator ~ name ~ ".o");
	}

	fn genVoltExeBc(name: string) string
	{
		return cleanPath(buildDir ~ dirSeparator ~ name ~ ".bc");
	}

	fn genVoltExeDep(name: string) string
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
