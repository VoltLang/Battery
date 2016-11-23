---
layout: page
title: Battery Documentation
permalink: /doc/battery
---

#Introduction

Battery is a tool for building Volt programs. In the future it will fetch code and more. But for now, it builds programs.

##How To Use

Battery makes some assumptions about project structure. Your source code will be in a directory named `src`. If your project is an executable, its entry point will be in `src/main.volt`. If you have tests, they will be in the `test` directory. So for a simple executable project that only depends on Watt (Volt's standard library, you might have your code in `src/main.volt`:

	module main;

	import watt.io;

	fn main() i32
	{
		writeln("Hello, world.");
		return 0;
	}

Hardly earth shattering stuff, but every great project starts somewhere. So to build that, we describe the project briefly in a `battery.txt` file in the root directory:

	--dep
	watt

`--dep` tells battery of a project dependency (something it needs to work) and then next line names it: watt. And that's all. No matter how many modules you add to your project, how labyrinthine your project structure becomes, as long as all the modules are under the `src` directory, Battery will find them.

In the future, we'll have jetpacks. Also, Battery will know where watt lives on the internet and will fetch it for you. But for now, we'll have to do a little legwork. Once you have the Volta and Watt source code somewhere on your system, we first invoke the `config` command, to get Battery to set up the build:

	battery config /path/to/Volta /path/to/Watt .

And if that's gone well, we can now build:

	battery build

This will build everything (including Volta!) and you'll have a shiny new program.

Sometimes build steps are a little more complicated. Battery lives in the real world. Here's a real example from a project with a couple more dependencies:

	--dep
	watt
	--dep
	amp
	--if-msvc
	-l
	SDL2.lib
	--if-osx
	--if-linux
	--cmd
	sdl2-config --libs

We'll go in depth on the commands in a later section. For now, notice we can do different things depending on the platform, and even run external tools to get library names and so on.

##Commands

Battery is built around a few 'commands'. These are our verbs. They are as follows:

	config
	build
	test
	help

All are invoked using `battery <command name>`. We used the `config` and `build` commands in the previous section.

###Help

This command doesn't do anything but give information. This command can give you a quick reminder on how to use Battery, or more in depth documentation on the various commands. `battery help config` will give help on the `config` command, for instance.

###Config

We've seen the `config` command already. And we've also seen some of the command line arguments it can take. `battery.txt` isn't particularly special -- it's just a list of parameters, like `--dep`, that tell it about your project. Battery command parameters come after the command; it's `battery config --dep watt`, not `battery --dep watt config`.

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

###Build

Actually performs the build. If there's a `test` folder, and Tesla is in the `PATH` (or specified at config time with `--cmd-tesla`), the tests will be run after the build completes. If the build failed, the return value will be non-zero. This only works after config has been run.

###Test

Runs tests if the `test` directory is present. Runs `build` if it has to.
