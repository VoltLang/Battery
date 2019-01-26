// Copyright 2016-2018, Jakob Bornecrantz.
// SPDX-License-Identifier: BSL-1.0
/*!
 * Functions for parsing Make compatible dependancy files.
 */
module build.util.make;

import core.exception;

import watt.text.path;
import watt.text.sink;
import watt.text.string;
import watt.io.file;
import watt.process.cmd;

import build.core;


fn importDepFile(ins: Instance, file: SinkArg)
{
	if (!isFile(file)) {
		return;
	}

	str := cast(char[])read(file);

	last: size_t;
	skip: bool;
	newline: bool;

	foreach (i, char c; str) {
		switch (c) {
		case '\n':
			newline = true;
			break;
		case '\r':
			newline = true;
			break;
		case '\\':
			skip = true;
			break;
		default:
			if (newline && !skip) {
				parseDeps(ins, file, str[last .. i]);
				last = i;
			}
			newline = false;
			skip = false;
		}
	}
	if (newline && !skip) {
		parseDeps(ins, file, str[last .. $]);
	}
}

fn parseDeps(ins: Instance, filename: SinkArg, text: SinkArg)
{
	ret := parseArguments(text);

	if (ret.length < 2) {
		return;
	}

	if (ret[0].length < 2 ||
	    !endsWith(ret[0], ":")) {
		err := new string("Invalid dep file: ", filename);
		throw new Exception(err);
	}

	f := ins.file(normalisePath(ret[0][0 .. $-1]));
	foreach (d; ret[1 .. $]) {
		f.deps ~= ins.file(normalisePath(d));
	}
}
