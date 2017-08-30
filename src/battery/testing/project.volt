// Copyright © 2012-2016, Jakob Bornecrantz.  All rights reserved.
// See copyright notice in src/volt/license.d (BOOST ver. 1.0).
module battery.testing.project;

import battery.interfaces;


class TestProject
{
public:
	name: string;
	paths: string[];
	commands: Command[string];

public:
	this(name: string, paths: string[])
	{
		this.name = name;
		this.paths = paths;
	}

	fn addCommand(id: string, command: Command)
	{
		commands[id] = command;
	}

	fn getCommand(id: string) Command
	{
		p := id in commands;
		if (p is null) {
			return null;
		} else {
			return *p;
		}
	}
}
