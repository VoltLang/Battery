// Copyright 2019, Collabora, Ltd.
// SPDX-License-Identifier: BSL-1.0
module battery.conf.cfg;

import core.exception;

import watt.text.format : format;
import watt.text.sink : Sink;
import watt.text.source : Source;
import watt.text.ascii : isAlpha, isAlphaNum, isWhite;
import watt.conv : toLower;

import battery.defines;


/*!
 * Evals a target string, throws @ref core.Exception on errors.
 */
fn eval(arch: Arch, platform: Platform, str: string, warning: Sink) bool
{
	te: TargetEval;
	return te.eval(arch, platform, str, warning);
}


private:

enum Token
{
	Not,    //<! `!`
	AndAnd, //<! `&&`
	OrOr,   //<! `||`
	OpenP,  //<! `(`
	CloseP, //<! `)`
	End,    //<! End of string

	Unknown,
	X86,
	X86_64,
	ARMHF,
	AArch64,
	OSX,
	Linux,
	MSVC,
}

/*!
 * Lexes a targets string.
 */
struct Lexer
{
private:
	mSrc: Source;
	mTokens: Token[];
	mWarning: Sink;


public:
	fn lex(text: string, warning: Sink) Token[]
	{
		mWarning = warning;
		mSrc = new Source(text, null);

		mSrc.skipWhitespace();

		for (; !mSrc.empty; ) with (Token) {
			f := mSrc.front;

			switch(f) {
			case '!':
				add(Not);
				mSrc.popFront();
				continue;
			case '&':
				ensureNextAndPop('&');
				add(AndAnd);
				mSrc.popFront();
				continue;
			case '|':
				ensureNextAndPop('|');
				add(OrOr);
				mSrc.popFront();
				continue;
			case '(':
				add(OpenP);
				mSrc.popFront();
				continue;
			case ')':
				add(CloseP);
				mSrc.popFront();
				continue;
			default:
				break;
			}

			if (f.isAlpha()) {
				parseIdent();
			} else if (mSrc.front.isWhite()) {
				mSrc.skipWhitespace();
			} else {
				throw abort(new "Invalid character ${mSrc.front}");
			}
		}

		add(Token.End);

		return mTokens;
	}

	fn parseIdent()
	{
		assert(mSrc.front.isAlpha());

		first := parseIdentPart();

		if (mSrc.front != '-') {
			add(first);
			return;
		}

		mSrc.popFront();
		if (!mSrc.front.isAlpha()) {
			throw abort("Expected alpha after '-'");
		}

		second := parseIdentPart();

		add(Token.OpenP);
		add(first);
		add(Token.AndAnd);
		add(second);
		add(Token.CloseP);
	}

	fn parseIdentPart() Token
	{
		mark := mSrc.save();
		do {
			mSrc.popFront();
		} while(mSrc.front.isAlphaNum() || mSrc.front == '_');

		str := mSrc.sliceFrom(mark);

		switch (str.toLower()) with (Token) {
		case "x86": return X86;
		case "x86_64": return X86_64;
		case "armhf": return ARMHF;
		case "aarch64": return AArch64;
		case "linux": return Linux;
		case "osx": return OSX;
		case "msvc": return MSVC;
		default:
			mWarning(format("unknown ident '%s'", str));
			return Unknown;
		}
	}

	fn add(token: Token)
	{
		mTokens ~= token;
	}

	fn ensureNextAndPop(n: dchar)
	{
		if (mSrc.following == n) {
			mSrc.popFront();
			return;
		}

		if (mSrc.following == '\0') {
			throw abort(new "Expected '${n}' got end of string");
		} else {
			throw abort(new "Expected '${n}' found '${mSrc.following}'");
		}
	}

	fn abort(str: string) Exception
	{
		return new Exception(str);
	}
}

/*!
 * Lexes, parses and evalulates a targets string.
 */
struct TargetEval
{
private:
	mArch: Arch;
	mPlatform: Platform;

	front: Token;
	empty: bool;

	mTokens: Token[];
	mIndex: size_t;


public:
	fn eval(arch: Arch, platform: Platform, str: string, warning: Sink) bool
	{
		p: Lexer;
		this.mTokens = p.lex(str, warning);
		assert(mTokens.length > 0);
		this.front = this.mTokens[0];
		this.mIndex = 0;
		this.mArch = arch;
		this.mPlatform = platform;
		this.empty = front == Token.End;

		return evalRoot();
	}


private:
	fn popFront()
	{
		if (mIndex + 1 < mTokens.length) {
			mIndex++;
		}

		front = mTokens[mIndex];
		empty = front == Token.End;
	}

	fn evalRoot() bool
	{
		value := evalStart(false);

		if (front == Token.CloseP) {
			throw abort("Left over ')");
		}
		return value;
	}

	fn evalStart(neg: bool) bool
	{
		bool value = false;

		final switch (front) with (Token) {
		case X86:     value = mArch == Arch.X86; break;
		case X86_64:  value = mArch == Arch.X86_64; break;
		case ARMHF:   value = mArch == Arch.ARMHF; break;
		case AArch64: value = mArch == Arch.AArch64; break;
		case OSX:     value = mPlatform == Platform.OSX; break;
		case Linux:   value = mPlatform == Platform.Linux; break;
		case MSVC:    value = mPlatform == Platform.MSVC; break;
		case Unknown: value = false; break;
		case Not:
			popFront();
			return evalStart(true);
		case OpenP:
			popFront();
			value = evalParan();
			break;
		case AndAnd:
			throw abortUnexpected("&&");
		case OrOr:
			throw abortUnexpected("||");
		case CloseP:
			throw abortUnexpected(")");
		case End:
			throw abort("Unexpected end of string!");
		}

		// Was there a neg in front of this value.
		if (neg) {
			value = !value;
		}

		popFront();

		return evalLink(value);
	}

	fn evalParan() bool
	{
		value := evalStart(false);

		if (front != Token.CloseP) {
			throw abort("Unclosed '(' at end of string!");
		}

		return value;
	}

	fn evalLink(first: bool) bool
	{
		link := front;

		final switch (front) with (Token) {
		case Not:
			throw abortUnexpected("!");
		case X86, X86_64, ARMHF, AArch64, OSX, Linux, MSVC, Unknown:
			throw abort("Unexpected identifier");
		case OpenP:
			throw abortUnexpected(")");
		case CloseP, End:
			return first;
		case AndAnd, OrOr:
			popFront();
			break;
		}

		second := evalStart(false);
		ret: bool;

		if (link == Token.AndAnd) {
			return first && second;
		} else {
			return first || second;
		}
	}

	fn abortUnexpected(str: string) Exception
	{
		return new Exception(new "Unexpected '${str}");	
	}

	fn abort(msg: string) Exception
	{
		return new Exception(msg);
	}
}

/+
fn testeval(arch: Arch, platform: Platform, str: string, expect: bool)
{
	te: TargetEval;
	if (te.eval(arch, platform, str) == expect) {
		io.writefln("passed: '%s'", str);
	} else {
		io.writefln("failed: '%s' !%s", str, expect);
	}
}

fn tests()
{
	testeval(Arch.X86, Platform.Linux, "linux", true);
	testeval(Arch.X86, Platform.OSX, "linux || osx", true);
	testeval(Arch.X86, Platform.Linux, "!aarch64-linux", true);
	testeval(Arch.X86, Platform.OSX, "(linux || osx) && !aarch64-linux", true);
	testeval(Arch.X86, Platform.Linux, "(linux || osx) && !aarch64", true);
	testeval(Arch.X86_64, Platform.Linux, "(linux || osx) && !x86_64", false);
}
+/
