// Copyright © 2017, Bernard Helyer.  All rights reserved.
// See copyright notice in src/battery/license.volt (BOOST ver. 1.0).
/*!
 * Process TOML configuration files.
 */
module battery.frontend.conf;

import file = watt.io.file;
import toml = watt.toml;

import battery.configuration;

fn parseTomlConfig(tomlFilename: string, path: string, c: Configuration, b: Project)
{
	root := toml.parse(cast(string)file.read(tomlFilename));
	b.deps = optionalStringArray(root, c, "dependencies");
}

private:

fn optionalStringArray(root: toml.Value, c: Configuration, key: string) string[]
{
	baseArr := optionalStringArray(root, key);
	platstring := c.platform.toString();
	if (root.hasKey(platstring)) {
		baseArr ~= optionalStringArray(root[platstring], key);
	}
	return baseArr;
}

fn optionalStringArray(root: toml.Value, key:string) string[]
{
	if (!root.hasKey(key)) {
		return null;
	}
	arr := root[key].array();
	strArray := new string[](arr.length);
	for (i: size_t = 0; i < arr.length; ++i) {
		strArray[i] = arr[i].str();
	}
	return strArray;
}
