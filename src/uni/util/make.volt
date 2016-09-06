// Copyright © 2016, Jakob Bornecrantz.  All rights reserved.
// See copyright notice in src/battery/license.volt (BOOST ver. 1.0).
module uni.util.make;

import core.exception;

import watt.text.path;
import watt.text.sink;
import watt.text.string;
import watt.io.file;
import watt.process.cmd;

import uni.core;


fn importDepFile(ins: Instance, file: SinkArg)
{
	if (!isFile(file)) {
		return;
	}

	str := cast(char[])read(file);

	last: size_t;
	skip: bool;
	foreach (i, char c; str) {
		switch (c) {
		case '\n':
			if (!skip) {
				parseDeps(ins, file, str[last .. i]);
				last = i;
			}
			skip = false;
			break;
		case '\\':
			skip = true;
			break;
		default:
			skip = false;
		}
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

	f := ins.file(normalizePath(ret[0][0 .. $-1]));
	foreach (d; ret[1 .. $]) {
		f.deps ~= ins.file(normalizePath(d));
	}
}
