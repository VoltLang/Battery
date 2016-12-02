module battery.testing.project;

import battery.interfaces;


class Project
{
public:
	name: string;
	path: string;
	commands: Command[string];

public:
	this(name: string, path: string)
	{
		this.name = name;
		this.path = path;
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
