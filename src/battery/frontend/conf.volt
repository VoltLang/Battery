// Copyright 2017-2018, Bernard Helyer.
// SPDX-License-Identifier: BSL-1.0
/*!
 * Process TOML configuration files.
 */
module battery.frontend.conf;

import core.exception;

import io = watt.io;
import file = watt.io.file;
import toml = watt.toml;
import wpath = watt.path;
import text = [watt.text.path, watt.process.cmd, watt.text.sink];
import process = watt.process.pipe;
import semver = watt.text.semver;

import platformEval = battery.conf.platform;
import cfgEval = battery.conf.cfg;
import llvmConf = battery.frontend.llvmConf;

import battery.configuration;
import battery.util.parsing;
import battery.util.log;

private global log: Logger = {"frontend.conf"};


fn parseTomlConfig(tomlFilename: string, path: string, d: Driver, c: Configuration, b: Project)
{
	log.info(new "Parsing '${tomlFilename}'");

	assert(file.exists(tomlFilename), "Toml file doesn't exists! " ~ tomlFilename);


	root := toml.parse(cast(string)file.read(tomlFilename));

	verifyKeys(root, tomlFilename, d);

	fn setIfNonEmpty(ref s: string, val: string)
	{
		if (val == "") {
			return;
		}
		s = val;
	}

	if (root.hasKey(CfgTable) && root.hasKey(PlatformTable)) {
		d.info("Found '%s' in '%s' ignoring '%s'", CfgTable, tomlFilename, PlatformTable);
		root.removeKey(PlatformTable);
	}

	pruneCfgTable(root, d, c);
	prunePlatformTable(root, d, c);

	// Set values that apply to both Libs and Exes.
	b.name = optionalStringValue(root, d, c, NameKey);
	if (b.name is null) {
		d.abort("'%s': no 'name' property", tomlFilename);
	}
	b.deps           ~= optionalStringArray(root, d, c, DependenciesKey);
	b.scanForD       = optionalBoolValue  (root, d, c, ScanForDKey);
	b.llvmHack       = optionalBoolValue  (root, d, c, LLVMHackKey);
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
	b.srcS           ~= optionalPathArray(root, path, d, c, SFilesKey);
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

fn verifyKeys(root: toml.Value, tomlPath: string, d: Driver, prefix: string = null)
{
	keys := root.tableKeys();
	foreach (key; keys) {
		val := root[key];

		switch (key) {
		case PlatformTable:
			verifyPlatformTable(val, tomlPath, d, prefix);
			continue;
		case DependenciesKey, NameKey, OutputKey, ScanForDKey, IsTheRTKey,
			SrcDirKey, TestFilesKey, JsonOutputKey, LibsKey, LPathsKey, FrameworksKey, FPathsKey,
			StringPathKey, LDArgsKey, CCArgsKey, LinkArgsKey, LinkerArgsKey,
			AsmFilesKey, CFilesKey, SFilesKey, ObjFilesKey, VoltFilesKey, IdentKey, CommandKey, WarningKey,
			LlvmConfig, LLVMHackKey, CfgTable:
			continue;
		default:
			d.info(new "Warning: unknown key \"${prefix}${key}\" in config file '${tomlPath}'");
			break;
		}
	}
}

fn verifyPlatformTable(table: toml.Value, tomlPath: string, d: Driver, prefix: string)
{
	tableName := new "${prefix}${PlatformTable}";
	if (table.type != toml.Value.Type.Table) {
		d.abort(new "key \"${tableName}\" must be a table in config file '${tomlPath}'");
		return;
	}

	foreach (key; table.tableKeys()) {
		val := table[key];

		name := new "${tableName}.'${key}'";

		if (val.type != toml.Value.Type.Table) {
			d.abort(new "key \"${name}\" must be table in config file '${tomlPath}'");
			continue;
		}

		verifyKeys(val, tomlPath, d, new "${name}.");
	}
}

enum DependenciesKey = "dependencies";
enum PlatformTable   = "platform";
enum NameKey         = "name";
enum OutputKey       = "output";
enum ScanForDKey     = "scanForD";
enum LLVMHackKey     = "llvmHack";
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
enum SFilesKey       = "sFiles";
enum ObjFilesKey     = "objFiles";
enum VoltFilesKey    = "voltFiles";
enum IdentKey        = "versionIdentifiers";
enum CommandKey      = "commands";
enum WarningKey      = "warningsEnabled";
enum LlvmConfig      = "llvmConfig";
enum CfgTable        = "cfg";

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

fn evaluatePlatform(d: Driver, c: Configuration, key: string) bool
{
	try {
		return platformEval.eval(c.platform, key);
	} catch (Exception e) {
		d.abort(e.msg);
		return false;
	}
}

fn prunePlatformTable(root: toml.Value, d: Driver, c: Configuration)
{
	if (!root.hasKey(PlatformTable)) {
		return;
	}

	platformTable := root[PlatformTable];
	foreach (platformKey; platformTable.tableKeys()) {
		if (evaluatePlatform(d, c, platformKey)) {
			continue;
		}

		platformTable.removeKey(platformKey);
	}
}

fn evaluateCfg(d: Driver, c: Configuration, key: string) bool
{
	fn warn(str: text.SinkArg) {
		d.info("warning: In key '%s' %s", key, str);
	}

	ret: bool;
	try {
		ret = cfgEval.eval(c.arch, c.platform, key, warn);
	} catch (Exception e) {
		d.info("warning: In key '%s' %s", key, e.msg);
	}
	return ret;
}

fn pruneCfgTable(root: toml.Value, d: Driver, c: Configuration)
{
	if (!root.hasKey(CfgTable)) {
		return;
	}

	cfgTable := root[CfgTable];
	foreach (cfgKey; cfgTable.tableKeys()) {
		if (evaluateCfg(d, c, cfgKey)) {
			continue;
		}

		cfgTable.removeKey(cfgKey);
	}
}

alias Callback = scope dg (table: toml.Value);

fn onPlatform(root: toml.Value, d: Driver, c: Configuration, cb: Callback)
{
	if (!root.hasKey(PlatformTable)) {
		return;
	}

	foreach (value; root[PlatformTable].tableValues()) {
		cb(value);
	}
}

fn onTargets(root: toml.Value, d: Driver, c: Configuration, cb: Callback)
{
	if (!root.hasKey(CfgTable)) {
		return;
	}

	foreach (value; root[CfgTable].tableValues()) {
		cb(value);
	}	
}

fn optionalStringValue(root: toml.Value, d: Driver, c: Configuration, key: string) string
{
	base := optionalStringValue(root, key);
	fn call(table: toml.Value) {
		val := optionalStringValue(table, key);
		if (val != "") {
			base = val;
		}
	}

	onTargets(root, d, c, call);
	onPlatform(root, d, c, call);

	return base;
}

fn optionalBoolValue(root: toml.Value, d: Driver, c: Configuration, key: string) bool
{
	base := optionalBoolValue(root, key);
	fn call(table: toml.Value) {
		if (table.hasKey(key)) {
			base = optionalBoolValue(table, key);
		}
	}

	onTargets(root, d, c, call);
	onPlatform(root, d, c, call);

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
	fn call(table: toml.Value) {
		baseArr ~= optionalStringArray(table, key);
	}

	onTargets(root, d, c, call);
	onPlatform(root, d, c, call);

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
