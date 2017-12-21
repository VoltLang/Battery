---
layout: page
title: Battery Documentation
permalink: /doc/battery
---

# Introduction

Battery is a tool for building Volt programs. In the future it will fetch code and more. But for now, it builds programs.

## How To Use

Battery makes some assumptions about project structure. Your source code will be in a directory named `src`. If your project is an executable, its entry point will be in `src/main.volt`. If you have tests, they will be in the `test` directory. If there is a `res` folder, Volta will be told to look for string imports (`-J`) there. So for a simple executable project that only depends on Watt (Volt's standard library, you might have your code in `src/main.volt`:

	module main;

	import watt.io;

	fn main() i32
	{
		writeln("Hello, world.");
		return 0;
	}

Hardly earth shattering stuff, but every great project starts somewhere. So to build that, we describe the project briefly in a `battery.toml` file in the root directory:

	name = "hello"
	dependencies = ["watt"]

`dependencies` tells battery of a project dependency (something it needs to work) and then next line names it: watt. And that's all. No matter how many modules you add to your project, how labyrinthine your project structure becomes, as long as all the modules are under the `src` directory, Battery will find them.

In the future, we'll have jetpacks. Also, Battery will know where watt lives on the internet and will fetch it for you. But for now, we'll have to do a little legwork. Once you have the Volta and Watt source code somewhere on your system, we first invoke the `config` command, to get Battery to set up the build:

	battery config /path/to/Volta /path/to/Watt .

And if that's gone well, we can now build:

	battery build

This will build everything (including Volta!) and you'll have a shiny new program.

Sometimes build steps are a little more complicated. Battery lives in the real world. Here's a real example from a project with a couple more dependencies:

	name = "Oleum"
	dependencies = ["watt", "amp"]
	[platform.msvc]
	libraries = ["SDL2.lib"]
	[platform.'osx || linux']
	commands = ["sdl2-config --libs"]

We'll go in depth on the commands in a later section. For now, notice we can do different things depending on the platform, and even run external tools to get library names and so on.

## Projects And Subprojects

Battery organises things in terms of projects. In the example above, `Volta` is a project, as is `Watt`. They're given using local paths above, but in future URLs, and perhaps just their names will be enough for Battery to locate them. The important thing to understand is that a project is collection of code, that can be 'depended' upon, that is, required for another project to build. That is what the

	dependencies = ["watt"]

lines in the above `battery.toml` files are saying. "This project depends on `watt`, and requires it to build."

Projects can have subprojects. That is, projects that are children of another project. This is useful if individual pieces of your project are useful outside of the context of the larger one. Say you were writing an emulator for the smash arcade hit, *Cosmos Attackers*. The Silog S81 processor used by *Cosmos Attackers* was used in other arcade hits of the time, such as *Pack Mun*, and *Dug Dog*, so you might want to use your S81 emulator in other projects.

To make a project a child of another, simply place it in its parent's project folder. So your tree might look like

	cosmo_em
		src   // ui code, etc
		battery.toml
		s81
			battery.toml
			src

Then, in `cosmo_em`'s `battery.toml` (and any other project that wants to use your S81 emulator), add a `dependencies` of `["cosmo_em.s81"]`. Set `s81`'s `name` as `"cosmo_em.s81"`. Parents do not automatically depend on their children, nor do children on their parents. Other than the lookup syntax with `.`, subprojects behave just as regular projects.

## Project Name Restrictions

A project's name is based entirely on its folder name.

Project names must start with an alphabetical character, or an underscore, and the rest of the name must be either an alphabetical character, an underscore, or a digit.

If a project doesn't confirm to the above specification, the `config` step will fail with an error displaying the name that failed to validate.

## Commands

Battery is built around a few 'commands'. These are our verbs. They are as follows:

	config
	build
	test
	help
	init

All are invoked using `battery <command name>`. We used the `config` and `build` commands in the previous section.

### Help

This command doesn't do anything but give information. This command can give you a quick reminder on how to use Battery, or more in depth documentation on the various commands. `battery help config` will give help on the `config` command, for instance.

### Config

We've seen the `config` command already. Here are some flags that can affect it.

	--arch arch      Selects architecture (x86, x86_64).
	--platform plat  Selects platform (osx, msvc, linux).
	--exe            Force an executable target.
	--lib            Force a library target.
	--name name      Name the current target. This is used with the --dep parameter, for instance.
	--dep depname    Add a dependency.
	--src-I dir      Use a different source directory, instead of src.
	--cmd command    Run the command and treat the output as parameters.
	--cmd-(tool)     Specify an external tool location. e.g. Tesla, or nasm.
	-l lib           Add a library to link with.
	-L path          Add a path to search with libraries.
	-framework name  Add a framework to link with. (macOS only)
	-F path          Add a framework search path. (macOS only)
	-J path          Define a path for string import to look for files.
	-D ident         Define a new version flag.
	-o outputname    Set output (executable, etc) to outputname.
	--debug          Set debug mode.
	--Xld            Add an argument when invoking the ld linker.
	--Xcc            Add an argument when invoking the cc linker.
	--Xlink          Add an argument when invoking the MSVC link linker.
	--Xlinker        Add an argument when invoking all different linkers.
	--if-(platform)  Only do the following for (platform).
	--if-(arch)      Only do the following for (arch).

You probably recognise quite a few of these from Volta.

### Build

Actually performs the build. If there's a `test` folder, the tests will be run after the build completes. If the build failed, the return value will be non-zero. This only works after config has been run.

If you pass `--verbose` to this command, the exact commands that Battery runs will be printed.

### Init

Init will setup a very simple project skeleton for you. If invoked with no arguments, it will ask you for the project name, and whether it's a library or an executable. These answers can be given ahead of time with the `--init-name` and `--init-type` flags, respectively.

### Test

Runs tests if the `test` directory is present. Runs `build` if it has to. The tests are described in a [json](json.org) file named `battery.test.json`.

#### battery.test.json

The file contains an object. The various properties are documented below.

	pattern            a string, like "*.volt" or "test.volt" that
	                   describes what files contain tests. (non-optional).
	testCommandPrefix  a string that describes what lines that contain
	                   test commands (more on them later). (non-optional).
	macros             an object containing lists of commands that can be
	                   invoked with the macro: command. (optional).
	requiresAliases    an object containing strings that are expanded in
	                   requires commands. (more on them later). (optional).

#### Commands

Each individual test is described with various commands. The commands consist of a word and an argument, separated by a colon. The lines containing commands are prefixed by a string (usually a comment and a special character) given in `battery.test.json` with the `testCommandPrefix` property.

`run` runs a given command. If the return value is 0, then that `run` is considered okay. (This can be overriden with the `retval` command). There are some special variables that can be expanded:

	%s - the path to the test file
	%S - the path to the test directory
	%t - a unique name for that test -- useful for output filenames etc.
	%T - a unique output directory for that test.

So for instance. Let's say we were writing a C compiler, and we wanted battery to test it. Given a `pattern` of `hello.c`, and `testCommandPrefix` of `/*T `, a very simple C test could be as follows:

	/*T run:cc -o %t %s */
	/*T run:./%t */
	int main() { return 0; }

So if the compilation failed, or the output didn't return 0, then the test would be marked as a failure. What if we wanted our program to return 3? Or to test that the compilation failed? How would we do that? Enter the `retval` command:

	/*T retval:0 */
	/*T run:cc -o %t %s */
	/*T retval:3 */
	/*T run:./%t */
	int main() { return 3; }

The `retval` command gives the expected return value for the *next* `run` command that appears. Note that if you give one retval command, every run command must have an explicit retval command, even if you're expecting zero.

A good test suite has a lot of tests. And if you have a lot of tests of the same format, you don't want to have to specify the above every single time. `macro` will save the day here.

First, in our `battery.tests.json` file, add a "macros" property, and add a few entries.

	"macros": {
		"default": [
			"/*T run:cc -o %t %s */",
			"/*T run:./%t */"
		],
		"failure": [
			"/*T retval:1 */",
			"/*T run:cc -o %t %s */"
		]
	}

The `default` macro will be used for every test with no action. So our simplest test becomes:

	int main() { return 0; }

Then, we can check for failure in compilation with our `failure` macro. Use `macro:` and then the name of the macro to invoke. It will be as if the commands were written out explicitly.

	/*T macro:failure */
	int main() return 0 }

The `check` command checks the stdout and stderr of the runs, and passes if the given string occurs anywhere in that output, and fails otherwise.

	/*T check:hello, world */
	#include <stdio.h>
	int main() { printf("hello, world\n"); return 0; }

Multiple checks can be specified, and they must occur in order. They don't have to be adjacent, just earlier checks must occur before later checks.

The `requires` command allows you to check simple platform and architecture conditions, skipping platforms that fail. This allows you to check OS specific things in a clean fashion. The `requiresAliases` property of `battery.tests.json` allows you to define new keywords with the same expression syntax.

	requires:windows && !x86

This test will only be run on windows, and will be skipped on x86. These platforms and architectures are the same used elsewhere in battery, run `battery help config` for details.

And finally, `has-passed:no` denotes that you are aware that a test is failing, and not to mark it as a regression.

## battery.toml

A brief description of the battery toml format.

`battery.toml` is in the [toml](https://github.com/toml-lang/toml) format. It specifies project properties through various keys. Keys can be modified on a per platform basis through `platform` tables.

### Keys

```
dependencies		An array of name strings that this project depends on.
name				The name of the project. (string)
output				The name of the executable. (string)
scanForD			Internal use only.
isTheRT				Internal use only.
srcDir				Explicitly set the source directory. (string)
testFiles			Specify the test json files. (array of strings)
jsonOutput			Filename for JSON output. (string)
libraries			Libraries to link with. (array of strings)
libraryPaths		Paths that the linker should look in. (array of strings)
frameworks			Frameworks to link with. (macOS only) (array of strings)
frameworkPaths		Locations of frameworks. (macOS only) (array of strings)
stringPaths			The location for Volta's string imports. (array of strings)
ldArguments			Arguments to pass ld. (array of strings)
ccArguments			Arguments to pass cc. (array of strings)
linkArguments		Arguments to pass link. (array of strings)
linkerArguments		Arguments to pass the linker. (array of strings)
asmFiles			Files to assemble with nasm. (array of strings)
cFiles				Files to compile with clang. (array of strings)
objFiles			Files to link. (array of strings)
voltFiles			Additional files to compile. (array of strings)
versionIdentifiers	Version identifiers to set (array of strings)
commands			Commands to run, and parse `-l` and `-L` out of their output. (array of strings)
warningsEnabled		Tells the Volta compiler to generate warnings. (boolean)
```

Platform identifiers can be simple: `[platform.msvc]`. The second part can be a string: `[platform.'msvc']`. You can `&&` or `||` platforms, as well `!`ing them: `[platform.'!msvc && !macOS]`.
