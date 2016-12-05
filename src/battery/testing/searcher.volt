// Copyright © 2012-2016, Jakob Bornecrantz.  All rights reserved.
// See copyright notice in src/volt/license.d (BOOST ver. 1.0).
module battery.testing.searcher;

import watt.path;
import watt.io;
import watt.io.file;
import watt.text.format;
import json = watt.text.json;
import core.exception;
import core.stdc.stdio;

import battery.configuration;
import battery.testing.test;
import battery.testing.legacy;


/**
 * Searches for tests cases.
 */
class Searcher
{
public:
	mTests: Test[];
	mCommandStore: Configuration;


public:
	this(cs: Configuration)
	{
		mCommandStore = cs;
	}

	fn search(dir: string, prefix: string) Test[]
	{
		search(dir, dir, prefix);

		return mTests;
	}


private:
	fn search(base: string, dir: string, prefix: string)
	{
		fn hit(file: string)
		{
			switch (file) {
			case "", ".", "..":
				return;
			case "battery.tests.json":
				t := dir ~ dirSeparator ~ file;
				searchJson(base, dir, prefix, t);
				writefln("Found new but not yet supported tests (%s)!", t);
				return;
			case "battery.tests.simple":
				searchSimple(dir, dir, prefix);
				return;
			default:
				fullpath := dir ~ dirSeparator ~ file;
				if (!isDir(fullpath)) {
					return;
				}
				search(base, fullpath, prefix);
				return;
			}
		}

		searchDir(dir, "*", hit);
	}

	fn searchSimple(base: string, dir: string, prefix: string)
	{
		fn hit(file: string) {
			switch (file) {
			case "", ".", "..", "deps", "mixin":
				return;
			case "test.volt":
				test := dir[base.length + 1 .. $];
				mTests ~= new Legacy(dir, test, mCommandStore, prefix);
				return;
			default:
				fullpath := dir ~ dirSeparator ~ file;
				if (!isDir(fullpath)) {
					return;
				}
				searchSimple(base, fullpath, prefix);
			}
		}

		searchDir(dir, "*", hit);
	}

	fn searchJson(base: string, dir: string, prefix: string, jsonPath: string)
	{
		btj: BatteryTestsJson;
		btj.parse(jsonPath);
	}
}

struct BatteryTestsJson
{
	pattern: string;

	fn parse(jsonPath: string)
	{
		fn error(msg: string)
		{
			throw new Exception(format("Malformed battery.tests.json: %s.", msg));
		}
		jsonTxt := cast(string)read(jsonPath);
		rootValue := json.parse(jsonTxt);
		if (rootValue.type() != json.DomType.OBJECT) {
			error("root node is not an object");
		}
		if (!rootValue.hasObjectKey("pattern")) {
			error("root object does not declare pattern field");
		}
		patternValue := rootValue.lookupObjectKey("pattern");
		if (patternValue.type() != json.DomType.STRING) {
			error("pattern field is not a string");
		}

		pattern = patternValue.str();
	}
}
