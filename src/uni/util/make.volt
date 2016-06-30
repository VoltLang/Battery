// Copyright © 2016, Jakob Bornecrantz.  All rights reserved.
// See copyright notice in src/battery/license.volt (BOOST ver. 1.0).
module uni.util.make;

static import object;

import watt.text.path;
import watt.text.sink;
import watt.text.string;
import watt.io.file;
import watt.process.cmd;

import uni.core;


void importDepFile(Instance ins, SinkArg file)
{
	if (!isFile(file)) {
		return;
	}

	str := cast(char[])read(file);

	size_t last;
	bool skip;
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

void parseDeps(Instance ins, SinkArg filename, SinkArg text)
{
	ret := parseArguments(text);

	if (ret.length < 2) {
		return;
	}

	if (ret[0].length < 2 ||
	    !endsWith(ret[0], ":")) {
		throw new object.Exception("Invalid dep file: " ~ filename);
	}

	f := ins.file(normalizePath(ret[0][0 .. $-1]));
	foreach (d; ret[1 .. $]) {
		f.deps ~= ins.file(normalizePath(d));
	}
}
