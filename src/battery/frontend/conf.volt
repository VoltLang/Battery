// Copyright © 2017, Bernard Helyer.  All rights reserved.
// See copyright notice in src/battery/license.volt (BOOST ver. 1.0).
/*!
 * Process TOML configuration files.
 */
module battery.frontend.conf;

import io = watt.io;
import file = watt.io.file;
import toml = watt.toml;
import wpath = watt.path;
import text = [watt.text.string, watt.text.ascii, watt.text.path, watt.process.cmd];
import process = watt.process.pipe;
import semver = watt.text.semver;

import llvmConf = battery.frontend.llvmConf;

import battery.configuration;

fn parseTomlConfig(tomlFilename: string, path: string, d: Driver, c: Configuration, b: Project)
{
	root := toml.parse(cast(string)file.read(tomlFilename));

	verifyKeys(root, tomlFilename, d);

	fn setIfNonEmpty(ref s: string, val: string)
	{
		if (val == "") {
			return;
		}
		s = val;
	}

	// Set values that apply to both Libs and Exes.
	b.name = optionalStringValue(root, d, c, NameKey);
	if (b.name is null) {
		d.abort("'%s': no 'name' property", tomlFilename);
	}
	b.deps           ~= optionalStringArray(root, d, c, DependenciesKey);
	b.scanForD       = optionalBoolValue  (root, d, c, ScanForDKey);
	b.warningsEnabled= optionalBoolValue(root, d, c, WarningKey);
	setIfNonEmpty(ref b.srcDir,  makePath(path, optionalStringValue(root, d, c, SrcDirKey)));
	setIfNonEmpty(ref b.jsonOutput, makePath(path, optionalStringValue(root, d, c, JsonOutputKey)));
	b.testFiles      ~= optionalPathArray(root, path, d, c, TestFilesKey);
	b.libs           ~= optionalStringArray(root,  d, c, LibsKey);
	b.libPaths       ~= optionalStringArray(root, d, c, LPathsKey);
	b.frameworks     ~= optionalStringArray(root, d, c, FrameworksKey);
	b.frameworkPaths ~= optionalStringArray(root, d, c, FPathsKey);
	b.stringPaths    ~= optionalPathArray(root, path, d, c, StringPathKey);
	b.xld            ~= optionalStringArray(root, d, c, LDArgsKey);
	b.xcc            ~= optionalStringArray(root, d, c, CCArgsKey);
	b.xlink          ~= optionalStringArray(root, d, c, LinkArgsKey);
	b.xlinker        ~= optionalStringArray(root, d, c, LinkerArgsKey);
	b.srcAsm         ~= optionalPathArray(root, path, d, c, AsmFilesKey);
	cmdarr           := optionalStringArray(root, d, c, CommandKey);
	foreach (cmd; cmdarr) {
		parseCommand(cmd, c, b);
	}

	// Set values that apply to Exes only.
	exe  := cast(Exe)b;
	if (exe !is null) {
		setIfNonEmpty(ref exe.bin, makePath(path, optionalStringValue(root, d, c, OutputKey)));
		exe.srcC     ~= optionalPathArray(root, path, d, c, CFilesKey);
		exe.srcVolt  ~= optionalPathArray(root, path, d, c, VoltFilesKey);
		exe.srcObj   ~= optionalPathArray(root, path, d, c, ObjFilesKey);
		exe.defs     ~= optionalStringArray(root, d, c, IdentKey);
		return;
	}

	// Set values that apply to Libs only.
	lib := cast(Lib)b;
	if (lib !is null) {
		lib.isTheRT = optionalBoolValue(root, d, c, IsTheRTKey);
		return;
	}
}

private:

fn verifyKeys(root: toml.Value, tomlPath: string, d: Driver)
{
	keys := root.tableKeys();
	foreach (key; keys) {
		val := root[key];
		if (val.type == toml.Value.Type.Table) {
			verifyKeys(val, tomlPath, d);
			continue;
		}
		switch (key) {
		case DependenciesKey, PlatformTable, NameKey, OutputKey, ScanForDKey, IsTheRTKey,
			SrcDirKey, TestFilesKey, JsonOutputKey, LibsKey, LPathsKey, FrameworksKey, FPathsKey,
			StringPathKey, LDArgsKey, CCArgsKey, LinkArgsKey, LinkerArgsKey,
			AsmFilesKey, CFilesKey, ObjFilesKey, VoltFilesKey, IdentKey, CommandKey, WarningKey,
			LlvmConfig:
			continue;
		default:
			d.info(new "Warning: unknown key '${key}' in config file '${tomlPath}'");
			break;
		}
	}
}

enum DependenciesKey = "dependencies";
enum PlatformTable   = "platform";
enum NameKey         = "name";
enum OutputKey       = "output";
enum ScanForDKey     = "scanForD";
enum IsTheRTKey      = "isTheRT";
enum SrcDirKey       = "srcDir";
enum TestFilesKey    = "testFiles";
enum JsonOutputKey   = "jsonOutput";
enum LibsKey         = "libraries";
enum LPathsKey       = "libraryPaths";
enum FrameworksKey   = "frameworks";
enum FPathsKey       = "frameworkPaths";
enum StringPathKey   = "stringPaths";
enum LDArgsKey       = "ldArguments";
enum CCArgsKey       = "ccArguments";
enum LinkArgsKey     = "linkArguments";
enum LinkerArgsKey   = "linkerArguments";
enum AsmFilesKey     = "asmFiles";
enum CFilesKey       = "cFiles";
enum ObjFilesKey     = "objFiles";
enum VoltFilesKey    = "voltFiles";
enum IdentKey        = "versionIdentifiers";
enum CommandKey      = "commands";
enum WarningKey      = "warningsEnabled";
enum LlvmConfig      = "llvmConfig";

fn parseCommand(cmd: string, c: Configuration, b: Project)
{
	args := text.parseArguments(cmd);
	if (args.length == 0) {
		return;
	}

	cmd = args[0];
	args = args[1 .. $];

	// See if there is a cmd added with this name.
	// Helps llvm-config to match what for the entire build.
	if (tool := c.getTool(cmd)) {
		cmd = tool.cmd;
		args = tool.args ~ args;
	}

	str := process.getOutput(cmd, args);
	args = text.parseArguments(str);

	nextLib := false;
	nextPath := false;
	foreach (arg; args) {
		if (nextLib) {
			b.libs ~= arg;
			nextLib = false;
			continue;
		} else if (nextPath) {
			b.libPaths ~= arg;
			nextPath = false;
			continue;
		}
		if (arg.length < 2) {
			continue;
		}
		if (arg.length == 2) {
			if (arg == "-l") {
				nextLib = true;
			} else if (arg == "-L") {
				nextPath = true;
			}
			continue;
		}
		if (arg[0 .. 2] == "-l") {
			b.libs ~= arg[2 .. $];
		} else if (arg[0 .. 2] == "-L") {
			b.libPaths ~= arg[2 .. $];
		}
	}
}

fn makePath(path: string, flag: string) string
{
	if (flag == "") {
		return "";
	}
	str := new string(path, flag);
	return text.normalisePath(str);
}

fn optionalStringValue(root: toml.Value, d: Driver, c: Configuration, key: string) string
{
	base := optionalStringValue(root, key);
	if (root.hasKey(PlatformTable)) {
		platformTable := root[PlatformTable];
		foreach (platformKey; platformTable.tableKeys()) {
			if (evaluatePlatformConditional(d, c, platformKey)) {
				val := optionalStringValue(platformTable[platformKey], key);
				if (val != "") {
					base = val;
				}
			}
		}
	}
	return base;
}

fn optionalBoolValue(root: toml.Value, d: Driver, c: Configuration, key: string) bool
{
	base := optionalBoolValue(root, key);
	if (root.hasKey(PlatformTable)) {
		platformTable := root[PlatformTable];
		foreach (platformKey; platformTable.tableKeys()) {
			if (evaluatePlatformConditional(d, c, platformKey)) {
				if (platformTable[platformKey].hasKey(key)) {
					base = optionalBoolValue(platformTable[platformKey], key);
				}
			}
		}
	}
	return base;
}

fn optionalPathArray(root: toml.Value, path: string, d: Driver, c: Configuration, key: string) string[]
{
	array := optionalStringArray(root, d, c, key);
	foreach (ref element; array) {
		element = makePath(path, element);
	}
	return array;
}

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

fn optionalStringValue(root: toml.Value, key: string) string
{
	if (!root.hasKey(key)) {
		return null;
	}
	return root[key].str();
}

fn optionalBoolValue(root: toml.Value, key: string) bool
{
	if (!root.hasKey(key)) {
		return false;
	}
	return root[key].boolean();
}

fn optionalStringArray(root: toml.Value, key: string) string[]
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
	this(d: Driver, originalKey: string, ref key: string)
	{
		skipWhitespace(ref key);
		failIfEmpty(d, originalKey, key);
		not = get(ref key, '!');
		assert(key[0] != '!');
		skipWhitespace(ref key);
		failIfEmpty(d, originalKey, key);
		platformString := "";
		while (key.length > 0 && text.isAlpha(key[0])) {
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
		while (key.length > 0 && text.isWhite(key[0])) {
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
	base := new PlatformComponent(d, originalKey, ref key);
	current := base;
	while (current.link != PlatformComponent.Link.None && key.length > 0) {
		current.next = new PlatformComponent(d, originalKey, ref key);
		current = current.next;
	}
	if (current.link != PlatformComponent.Link.None || key.length != 0) {
		d.abort(new "malformed platform expression: \"${originalKey}\"");
	}
	return base;
}
