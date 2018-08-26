// Copyright 2012-2018, Jakob Bornecrantz.
// SPDX-License-Identifier: BSL-1.0
module battery.testing.project;

import battery.commonInterfaces;


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
