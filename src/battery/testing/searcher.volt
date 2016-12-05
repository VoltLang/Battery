// Copyright © 2012-2016, Jakob Bornecrantz.  All rights reserved.
// See copyright notice in src/volt/license.d (BOOST ver. 1.0).
module battery.testing.searcher;

import watt.path;
import watt.io;
import watt.io.file;
import watt.text.format;
import watt.text.string;
import json = watt.text.json;
import core.exception;
import core.stdc.stdio;

import battery.configuration;
import battery.testing.test;
import battery.testing.legacy;
import battery.testing.regular;


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
				btj: BatteryTestsJson;
				btj.parse(dir ~ dirSeparator ~ file);
				searchJson(dir, dir, prefix, ref btj);
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

	fn searchJson(base: string, dir: string, prefix: string, ref btj: BatteryTestsJson)
	{
		fn hit(file: string) {
			switch (file) {
			case "", ".", "..":
				return;
			default:
				if (globMatch(file, btj.pattern)) {
					test := dir[base.length + 1 .. $];
					mTests ~= new Regular(dir, test, file,
						btj.testCommandPrefix, prefix, mCommandStore);
					return;
				}
				fullpath := dir ~ dirSeparator ~ file;
				if (!isDir(fullpath)) {
					return;
				}
				searchJson(base, fullpath, prefix, ref btj);
			}
		}

		searchDir(dir, "*", hit);
	}
}

struct BatteryTestsJson
{
	pattern: string;
	testCommandPrefix: string;

	fn parse(jsonPath: string)
	{
		fn error(msg: string)
		{
			throw new Exception(format("Malformed battery.tests.json: %s.", msg));
		}

		jsonTxt := cast(string)read(jsonPath);
		rootValue := json.parse(jsonTxt);
		if (rootValue.type() != json.DomType.OBJECT) {
			error("root node not an object");
		}

		fn getStringField(fieldName: string) string
		{
			if (!rootValue.hasObjectKey(fieldName)) {
				error(format("root object does not declare field '%s'", fieldName));
			}
			val := rootValue.lookupObjectKey(fieldName);
			if (val.type() != json.DomType.STRING) {
				error(format("field '%s' is not a string", fieldName));
			}
			return val.str();
		}

		pattern = getStringField("pattern");
		testCommandPrefix = getStringField("testCommandPrefix");
	}
}
