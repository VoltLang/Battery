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
import battery.testing.project;
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

	fn search(project: Project, dir: string) Test[]
	{
		search(project, dir, dir);

		return mTests;
	}


private:
	fn search(project: Project, base: string, dir: string)
	{
		fn hit(file: string)
		{
			switch (file) {
			case "", ".", "..":
				return;
			case "battery.tests.json":
				btj: BatteryTestsJson;
				btj.parse(dir ~ dirSeparator ~ file);
				searchJson(project, dir, dir, ref btj);
				return;
			case "battery.tests.simple":
				searchSimple(project, dir, dir);
				return;
			default:
				fullpath := dir ~ dirSeparator ~ file;
				if (!isDir(fullpath)) {
					return;
				}
				search(project, base, fullpath);
				return;
			}
		}

		searchDir(dir, "*", hit);
	}

	fn searchSimple(project: Project, base: string, dir: string)
	{
		fn hit(file: string) {
			switch (file) {
			case "", ".", "..", "deps", "mixin":
				return;
			case "test.volt":
				test := dir[base.length + 1 .. $];
				mTests ~= new Legacy(dir, test, mCommandStore, project);
				return;
			default:
				fullpath := dir ~ dirSeparator ~ file;
				if (!isDir(fullpath)) {
					return;
				}
				searchSimple(project, base, fullpath);
			}
		}

		searchDir(dir, "*", hit);
	}

	fn searchJson(project: Project, base: string, dir: string, ref btj: BatteryTestsJson)
	{
		fn hit(file: string) {
			switch (file) {
			case "", ".", "..":
				return;
			default:
				if (globMatch(file, btj.pattern)) {
					test := dir[base.length + 1 .. $];
					mTests ~= new Regular(dir, test, file,
						btj.testCommandPrefix, project, mCommandStore,
						btj.defaultCommands);
					return;
				}
				fullpath := dir ~ dirSeparator ~ file;
				if (!isDir(fullpath)) {
					return;
				}
				searchJson(project, base, fullpath, ref btj);
			}
		}

		searchDir(dir, "*", hit);
	}
}

struct BatteryTestsJson
{
	pattern: string;
	testCommandPrefix: string;
	defaultCommands: string[];

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

		fn getStringArray(fieldName: string) string[]
		{
			if (!rootValue.hasObjectKey("defaultCommands")) {
				error(format("root object does not declare field '%s'", fieldName));
			}
			val := rootValue.lookupObjectKey(fieldName);
			if (val.type() != json.DomType.ARRAY) {
				error(format("field '%s' is not an array of strings", fieldName));
			}
			vals := val.array();
			strings := new string[](vals.length);
			for (size_t i = 0; i < strings.length; ++i) {
				if (vals[i].type() != json.DomType.STRING) {
					error(format("%s element number %s is not a string",
						fieldName, i));
				}
				strings[i] = vals[i].str();
			}
			return strings;
		}

		pattern = getStringField("pattern");
		testCommandPrefix = getStringField("testCommandPrefix");
		if (rootValue.hasObjectKey("defaultCommands")) {
			defaultCommands = getStringArray("defaultCommands");
		}
	}
}
