// Copyright © 2017, Bernard Helyer.  All rights reserved.
// See copyright notice in src/battery/license.volt (BOOST ver. 1.0).
/*!
 * Process TOML configuration files.
 */
module battery.frontend.conf;

import file = watt.io.file;
import toml = watt.toml;
import str = [watt.text.string, watt.text.ascii];

import battery.configuration;

fn parseTomlConfig(tomlFilename: string, path: string, d: Driver, c: Configuration, b: Project)
{
	root := toml.parse(cast(string)file.read(tomlFilename));
	b.deps = optionalStringArray(root, d, c, DependenciesKey);
}

private:

enum DependenciesKey = "dependencies";
enum PlatformTable   = "platform";

fn optionalStringArray(root: toml.Value, d: Driver, c: Configuration, key: string) string[]
{
	baseArr := optionalStringArray(root, key);
	if (root.hasKey(PlatformTable)) {
		platformTable := root[PlatformTable];
		foreach (platformKey; platformTable.tableKeys()) {
			if (evaluatePlatformConditional(d, c, platformKey)) {
				baseArr ~= optionalStringArray(platformTable[platformKey], key);
			}
		}
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

class PlatformComponent
{
	enum Link
	{
		None,
		And,
		Or,
	}

	not: bool;
	platform: Platform;
	link: Link;
	next: PlatformComponent;

	/*!
	 * Given a string, parse out one link in the platform chain.
	 *
	 * e.g., give this "!msvc && linux" and it will advance `key`, eating
	 * '!msvc && ', set `not` to `true`, set platform to MSVC, and set `link`
	 * to `Link.And`.
	 *
	 * The only valid characters are ASCII letters, !, |, and whitespace,
	 * so this code does no unicode processing, and assumes ASCII.
	 */
	this(d: Driver, originalKey: string, ptrkey: string*)
	{
		// This is a workaround for a Volta bug (functions 56). @todo
		key := *ptrkey;
		scope (exit) *ptrkey = key;

		skipWhitespace(ref key);
		failIfEmpty(d, originalKey, key);
		not = get(ref key, '!');
		assert(key[0] != '!');
		skipWhitespace(ref key);
		failIfEmpty(d, originalKey, key);
		platformString := "";
		while (key.length > 0 && str.isAlpha(key[0])) {
			platformString ~= key[0];
			key = key[1 .. $];
		}
		if (!isPlatform(platformString)) {
			d.abort(new "unknown platform string \"${platformString}\"");
		}
		platform = stringToPlatform(platformString);
		skipWhitespace(ref key);
		if (key.length == 0) {
			link = Link.None;
			return;
		}
		switch (key[0]) {
		case '|':
			get(ref key, '|');
			if (!get(ref key, '|')) {
				d.abort(new "malformed platform string: \"${originalKey}\"");
				break;
			}
			link = Link.Or;
			break;
		case '&':
			get(ref key, '&');
			if (!get(ref key, '&')) {
				d.abort(new "malformed platform string: \"${originalKey}\"");
				break;
			}
			link = Link.And;
			break;
		default:
			d.abort(new "malformed platform string: \"${originalKey}\"");
			break;
		}
		skipWhitespace(ref key);
	}

	fn evaluate(c: Configuration) bool
	{
		result := not ? platform != c.platform : platform == c.platform;
		final switch (link) with (PlatformComponent.Link) {
		case None: return result;
		case And : return result && next.evaluate(c);
		case Or  : return result || next.evaluate(c);
		}
	}

	private fn get(ref key: string, c: dchar) bool
	{
		if (key.length == 0 || key[0] != c) {
			return false;
		}
		key = key[1 .. $];
		return true;
	}

	private fn skipWhitespace(ref key: string)
	{
		while (key.length > 0 && str.isWhite(key[0])) {
			key = key[1 .. $];
		}
	}

	private fn failIfEmpty(d: Driver, originalKey: string, key: string)
	{
		if (key.length == 0) {
			d.abort(new "malformed platform key \"${originalKey}\"");
		}
	}
}

fn evaluatePlatformConditional(d: Driver, c: Configuration, key: string) bool
{
	platformChain := constructPlatformChain(d, ref key);
	return platformChain.evaluate(c);
}

fn constructPlatformChain(d: Driver, ref key: string) PlatformComponent
{
	originalKey := key;
	base := new PlatformComponent(d, originalKey, &key);
	current := base;
	while (current.link != PlatformComponent.Link.None && key.length > 0) {
		current.next = new PlatformComponent(d, originalKey, &key);
		current = current.next;
	}
	if (current.link != PlatformComponent.Link.None || key.length != 0) {
		d.abort(new "malformed platform expression: \"${originalKey}\"");
	}
	return base;
}
