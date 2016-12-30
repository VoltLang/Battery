// Copyright © 2012-2016, Jakob Bornecrantz.  All rights reserved.
// See copyright notice in src/volt/license.d (BOOST ver. 1.0).
module battery.testing.btj;

import core.exception;
import watt.text.format;
import watt.io.file;
import json = watt.text.json;

/**
 * Parse the battery.tests.json.
 */
class BatteryTestsJson
{
	pattern: string;
	prefix: string;
	defaultCommands: string[];
	requiresAliases: string[string];
	macros: string[][string];

	/// How each command will start, 
	runPrefix: string;
	retvalPrefix: string;
	requiresPrefix: string;
	hasPassedPrefix: string;
	noDefaultPrefix: string;
	macroPrefix: string;
	checkPrefix: string;

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

		fn getStringArray(rv: json.Value, fieldName: string) string[]
		{
			if (!rv.hasObjectKey(fieldName)) {
				error(format("object does not declare field '%s'", fieldName));
			}
			val := rv.lookupObjectKey(fieldName);
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
		prefix = getStringField("testCommandPrefix");
		if (rootValue.hasObjectKey("defaultCommands")) {
			defaultCommands = getStringArray(rootValue, "defaultCommands");
		}

		if (rootValue.hasObjectKey("requiresAliases")) {
			aliasesObj := rootValue.lookupObjectKey("requiresAliases");
			keys := aliasesObj.keys();
			values := aliasesObj.values();
			foreach (i, key; keys) {
				requiresAliases[key] = values[i].str();
			}
		}

		if (rootValue.hasObjectKey("macros")) {
			macroObj := rootValue.lookupObjectKey("macros");
			keys := macroObj.keys();
			foreach (key; keys) {
				macros[key] = getStringArray(macroObj, key);
			}
		}

		calculatePrefixes();
	}

	fn calculatePrefixes()
	{
		runPrefix = prefix ~ "run:";
		retvalPrefix = prefix ~ "retval:";
		requiresPrefix = prefix ~ "requires:";
		hasPassedPrefix = prefix ~ "has-passed:no";
		noDefaultPrefix = prefix ~ "default:no";
		macroPrefix = prefix ~ "macro:";
		checkPrefix = prefix ~ "check:";
	}
}
