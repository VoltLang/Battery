// Copyright 2016-2018, Jakob Bornecrantz.
// SPDX-License-Identifier: BSL-1.0
/*!
 * File helpers.
 */
module battery.util.file;

import watt.text.string : splitLines, replace;
import io = watt.io.streams;
import watt.io.file : read, exists;
import toml = watt.toml;


fn getLinesFromFile(file: string, ref lines: string[]) bool
{
	if (!exists(file)) {
		return false;
	}

	src := cast(string) read(file);

	foreach (line; splitLines(src)) {
		if (line.length > 0 && line[0] != '#') {
			lines ~= line;
		}
	}
	return true;
}

fn getTomlConfig(file: string, out root: toml.Value) bool
{
	if (!exists(file)) {
		return false;
	}

	src := cast(string)read(file);
	root = toml.parse(src);
	return true;
}

fn getStringArray(array: toml.Value[]) string[]
{
	lines: string[];
	foreach (index, elementValue; array) {
		str := elementValue.str();
		if (str.length == 0 || str[0] == '#') {
			continue;
		}
		lines ~= elementValue.str();
	}
	return lines;
}

fn outputConfig(filename: string, ver: string, genArgs: string[],
	batteryTxts: string[], cacheArgs: string[][]...)
{
	ofs := new io.OutputFileStream(filename);

	fn ar(a: string[])
	{
		foreach (e; a) {
			s := e.replace(`\`, `\\`);
			ofs.writeln(new "\t\"${s}\",");
		}
	}

	fn arr(name: string, a: string[])
	{
		ofs.writeln(new "${name} = [");
		ar(a);
		ofs.writeln("]");
	}

	fn arrarr(name: string, a: string[][])
	{
		ofs.writeln(new "${name} = [");
		foreach (e; a) {
			ar(e);
		}
		ofs.writeln("]");
	}

	ofs.writeln("# This file is generated by 'battery config'. Do not edit.");
	ofs.writeln("[battery.config]");
	ofs.writeln("# The version of battery that generated this file.");
	ofs.writeln(new "version = \"${ver}\"");
	ofs.writeln("# If any of these are newer than this file, this will be regenerated.");
	arr("input", batteryTxts);
	ofs.writeln("# The arguments that will be used to regenerate this config file if needed.");
	arr("args", genArgs);
	ofs.writeln("# The saved internal configuration for this build.");
	arrarr("cache", cacheArgs);
	ofs.flush();
	ofs.close();
}
