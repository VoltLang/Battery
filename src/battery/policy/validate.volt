// Copyright © 2017-2018, Jakob Bornecrantz.  All rights reserved.
// See copyright notice in src/battery/license.volt (BOOST ver. 1.0).
module battery.policy.validate;

import watt.text.ascii : isAlpha, isAlphaNum;

import battery.interfaces;


fn validateProjectNameOrAbort(drv: Driver, name: string)
{
	reason := validateProjectName(name);

	if (reason.length == 0) {
		return;
	}

	drv.abort("error: '%s' is not a valid name, %s.", name, reason);
}

fn validateProjectNameOrInform(drv: Driver, name: string) bool
{
	reason := validateProjectName(name);

	if (reason.length > 0) {
		drv.info("error: '%s' is not a valid name, %s.", name, reason);
		drv.info("Valid names start with a letter or '_', and only contain");
		drv.info("letters, digits, and underscores.");
		return false;
	}

	return true;
}

fn validateProjectName(name: string) string
{
	state := NameState.Start;
	foreach (c: dchar; name) final switch (state) with (NameState) {
	case Start, Dot:
		if (!isAlpha(c) && c != '_') {
			return new "invalid starting character '${c}'";
		}
		state = Word;
		break;
	case Word:
		// We allow dots in name for sub-projects.
		if (c == '.') {
			state = Dot;
			continue;
		}
		if (!isAlphaNum(c) && c != '_') {
			return new "invalid character '${c}'";
		}
		break;
	}

	if (state == NameState.Start) {
		return "is empty";
	}

	if (state == NameState.Dot) {
		return "ends with '.'";
	}

	return null;
}

private enum NameState 
{
	Start,
	Word,
	Dot,
}
