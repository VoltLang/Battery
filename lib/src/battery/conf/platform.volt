// Copyright 2017-2019, Bernard Helyer.
// Copyright 2019, Collabora, Ltd.
// SPDX-License-Identifier: BSL-1.0
module battery.conf.platform;

import core.exception;
import battery.defines;
import text = [watt.text.string, watt.text.ascii, watt.text.path, watt.process.cmd];
import battery.util.parsing;


/*!
 * Evaluate a platform key.
 */
fn eval(platform: Platform, key: string) bool
{
	platformChain := constructPlatformChain(ref key);
	return platformChain.evaluate(platform);
}


private:

fn abort(str: string) Exception
{
	return new Exception(str);
}

fn constructPlatformChain(ref key: string) PlatformComponent
{
	originalKey := key;
	base := new PlatformComponent(originalKey, ref key);
	current := base;
	while (current.link != PlatformComponent.Link.None && key.length > 0) {
		current.next = new PlatformComponent(originalKey, ref key);
		current = current.next;
	}
	if (current.link != PlatformComponent.Link.None || key.length != 0) {
		throw abort(new "malformed platform expression: \"${originalKey}\"");
	}
	return base;
}

class PlatformComponent
{
	enum Link
	{
		None,
		And,
		Or,
	}

	mNot: bool;
	mPlatform: Platform;

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
	this(originalKey: string, ref key: string)
	{
		skipWhitespace(ref key);
		failIfEmpty(originalKey, key);
		mNot = get(ref key, '!');
		assert(key[0] != '!');
		skipWhitespace(ref key);
		failIfEmpty(originalKey, key);
		platformString := "";
		while (key.length > 0 && text.isAlpha(key[0])) {
			platformString ~= key[0];
			key = key[1 .. $];
		}
		if (!isPlatform(platformString)) {
			throw abort(new "unknown platform string \"${platformString}\"");
		}
		mPlatform = stringToPlatform(platformString);
		skipWhitespace(ref key);
		if (key.length == 0) {
			link = Link.None;
			return;
		}
		switch (key[0]) {
		case '|':
			get(ref key, '|');
			if (!get(ref key, '|')) {
				throw abort(new "malformed platform string: \"${originalKey}\"");
			}
			link = Link.Or;
			break;
		case '&':
			get(ref key, '&');
			if (!get(ref key, '&')) {
				throw abort(new "malformed platform string: \"${originalKey}\"");
			}
			link = Link.And;
			break;
		default:
			throw abort(new "malformed platform string: \"${originalKey}\"");
		}
		skipWhitespace(ref key);
	}

	fn evaluate(platform: Platform) bool
	{
		result := mNot ? mPlatform != platform : mPlatform == platform;
		final switch (link) with (PlatformComponent.Link) {
		case None: return result;
		case And : return result && next.evaluate(platform);
		case Or  : return result || next.evaluate(platform);
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
		while (key.length > 0 && text.isWhite(key[0])) {
			key = key[1 .. $];
		}
	}

	private fn failIfEmpty(originalKey: string, key: string)
	{
		if (key.length != 0) {
			return;
		}
		throw abort(new "malformed platform key \"${originalKey}\"");
	}
}
