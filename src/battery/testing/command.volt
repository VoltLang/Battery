// Copyright © 2016, Jakob Bornecrantz.  All rights reserved.
// See copyright notice in src/volt/license.d (BOOST ver. 1.0).
module battery.testing.command;

import core.exception : Exception;
import watt.text.format;
import file = watt.io.file;
import json = watt.text.json;

import battery.interfaces;

class CommandStore
{
public:
	store: Command[string];

	this(configPath: string)
	{
		if (configPath != "") {
			loadConfig(configPath);
		}
	}


public:
	fn addCmd(name: string, cmd: string, baseArgs: string[])
	{
		store[name] = new Command(cmd, baseArgs);
	}

	fn getCmd(name: string, args: string[],
	          out cmd: string, out outArgs: string[]) bool
	{
		c := name in store;
		if (c is null) {
			return false;
		}

		cmd = c.cmd;
		outArgs = c.args ~ args;

		return true;
	}

	fn loadConfig(configPath: string)
	{
		if (!file.exists(configPath)) {
			throw new Exception(format("bad config path '%s'", configPath));
		}
		cfgString := cast(string)file.read(configPath);
		cfgRoot := json.parse(cfgString);
		loadConfigFromRoot(cfgRoot);
	}

private:

	fn malformedConfig(reason: string)
	{
		throw new Exception(format("malformed config file: '%s'", reason));
	}

	global fn contains(arr: string[], val: string) bool
	{
		foreach (str; arr) {
			if (str == val) {
				return true;
			}
		}
		return false;
	}

	fn loadConfigFromRoot(root: json.Value)
	{
		if (root.type() != json.DomType.OBJECT) {
			malformedConfig("root is not an object");
		}
		if (!root.keys().contains("cmds")) {
			malformedConfig("root object does not contain 'cmds' key");
		}
		cmdsObj := root.lookupObjectKey("cmds");
		if (cmdsObj.type() != json.DomType.OBJECT) {
			malformedConfig("cmds key does not map to an object");
		}
		foreach (key; cmdsObj.keys()) {
			cmdRoot := cmdsObj.lookupObjectKey(key);
			if (cmdRoot.type() != json.DomType.OBJECT) {
				malformedConfig(format("command '%s' does not map to an object",
					key));
			}
			addCommandFromRoot(key, cmdRoot);
		}
	}

	fn addCommandFromRoot(key: string, root: json.Value)
	{
		assert(root.type() == json.DomType.OBJECT);
		if (!root.keys().contains("path")) {
			malformedConfig(format("command '%s' does not have 'path' property",
				key));
		}

		pathValue := root.lookupObjectKey("path");
		if (pathValue.type() != json.DomType.STRING) {
			malformedConfig(format("command '%s' has non-string 'path' property",
				key));
		}
		pathStr := pathValue.str();

		args: string[];
		if (root.keys().contains("args")) {
			argsValue := root.lookupObjectKey("args");
			if (argsValue.type() != json.DomType.ARRAY) {
				malformedConfig(format("command '%s' has non-array 'args' property",
					key));
			}
			argsArray := argsValue.array();
			args = new string[](argsArray.length);
			foreach (i, argsArrayValue; argsArray) {
				if (argsArrayValue.type() != json.DomType.STRING) {
					malformedConfig(format(
						"command '%s' has non-string arg element", key));
				}
				args[i] = argsArrayValue.str();
			}
		}

		addCmd(key, pathStr, args);
	}
}
