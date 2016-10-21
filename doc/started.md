---
layout: page
title: Beginning Battery
---

What?
---

Volt is a systems level language, and Battery is a build tool for that language. This document will not elaborate on Volt itself, find out more on [its homepage](volt-lang.org).

Why?
---

Volta, the main implementation of the Volt language, is a compiler. If you've used, say, a C compiler before, nothing about its operation should shock.

    $ volt hello.volt
    $ ./a.out
    Hello, world.
    $

"So", you think to yourself, "I'll just use *make* for my projects". It is true, a Makefile, or even a shell script, can do the job. But not so fast -- here's all you'll need in the project describing `battery.txt` file for battery to build a simple project that just depends on Watt, Volt's standard library.

    --dep
    watt

"That's all well and good, disembodied voice", you say, "but any simple example can look elegant. What does that project file look like for 1000s of interdependent modules? What then?"

Glad you asked.

    --dep
    watt

In short, Battery deals with the boring parts of building your project, not just for you, but for anyone interested in using it for themselves.

How?
---

Assuming you have a working Volta install (again, see our [homepage](volt-lang.org) for more details) and you want to use Battery, you'll need to start by downloading it. In the future, we hope to have Battery be downloaded as binary, and then have it fetch everything you'll need, but we're not there yet. Pardon our mess!

So head on over to the [GitHub repository](https://github.com/VoltLang/Battery) and clone the source tree. Run old faithful make and you should have a new battery executable that you can add to your PATH.

Magical Incantations
---

Given a project with a `battery.txt` file already present, these are the usual commands you will need to invoke.

    $ battery config /path/to/Volta /path/to/Watt .
	$ battery build

Simple as that. In the future, it will be even simpler, as Battery will eventually know how to fetch the source code for Volta and Watt from the aether, but for now we have to give it a helping hand.

What's Really Going On?
---

Battery will read the `battery.txt` file for any information it needs to successfully build the project, but if you lay your source out in the standard way (`src` directory), it will find everything that it can build and build it. In fact, it will first build a Volta executable for that project.

For more in-depth information, please refer to the rest of the Battery documentation.
