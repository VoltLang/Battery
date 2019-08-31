// Copyright 2017-2018, Bernard Helyer.
// Copyright 2017-2019, Jakob Bornecrantz.
// SPDX-License-Identifier: BSL-1.0
/*!
 * Process battery configuration TOML files.
 */
module battery.frontend.batteryConf;

import toml = watt.toml;
import getopt = watt.text.getopt;

import watt.text.string : replace, StringSink;
import watt.text.format : format;
import watt.text.path : concatenatePath;
import watt.io.file : exists, isFile, read;
import watt.path : fullPath, exists, dirName;

import battery.commonInterfaces;
import battery.defines;
import battery.util.log;


enum BatteryConfName = "battery.conf.toml";

private global log: Logger = {"frontend.batteryConf"};


/*!
 * This parses the argument `--conf` from `args`.
 */
fn parseArguments(drv: Driver, ref args: string[], out conf: string)
{
	if (!getopt.getopt(ref args, "conf", ref conf)) {
		log.info("Did not get any --conf argument");
		return;
	}

	if (!exists(conf)) {
		drv.abort("Got --conf '%s' as a argument but it did not exists", conf);
	}
}

fn loadFromFile(filename: string, out batConf: BatteryConfig) bool
{
	if (filename is null) {
		log.info("\tNo filename given!");
		return false;
	}

	if (!filename.isFile()) {
		log.info(new "The file '${filename}' doesn't exists or is not a file!");
		return false;
	}

	// Tidy up the filename.
	state: State;
	state.filename = fullPath(filename);
	state.path = dirName(filename);

	return loadBatteryConf(ref state, out batConf);
}

fn loadFromDir(path: string, out batConf: BatteryConfig) bool
{
	if (path is null) {
		log.info("\tNo path given!");
		return false;
	}

	filename := concatenatePath(path, BatteryConfName);
	if (!filename.isFile()) {
		log.info(new "The file '${filename}' doesn't exists or is not a file!");
		return false;
	}

	// Tidy up the filename.
	state: State;
	state.path = path;
	state.filename = fullPath(filename);

	return loadBatteryConf(ref state, out batConf);
}

fn loadBatteryConf(ref state: State, out batConf: BatteryConfig) bool
{
	if (!state.filename.isFile()) {
		log.info(new "The file '${state.filename}' doesn't exists or is not a file!");
		return false;
	}

	log.info(new "BatConf parsing ${state.filename}'");

	try {
		root := toml.parse(cast(string)read(state.filename));

		state.parseRoot(root, out batConf);
		batConf.filename = state.filename;	
	} catch (toml.TomlException e) {
		log.info(new "Failed to parse '${state.filename}'\n\t${e.msg}");
	}

	batConf.dump("Found");
	return true;
}




private:

struct State
{
	filename: string;
	path: string;
}

enum VoltaKey = "volta";
enum NasmKey = "nasm";

enum PkgsKey = "pkgs";
enum LLVMKey = "llvm";

enum LLVMArKey = "ar";
enum LLVMWasmLLD = "wasm-ld";
enum LLVMCKey = "llvmC";
enum LLVMLLDLinkKey = "lld-link";
enum LLVMClangKey = "clang";

fn parseRoot(ref state: State, table: toml.Value, out batConf: BatteryConfig)
{
	foreach (key; table.tableKeys()) {
		val := table[key];
		switch (key) {
		case LLVMKey:  state.parseLLVM(val,       ref batConf); break;
		case PkgsKey:  state.parsePaths(key, val, ref batConf.pkgs); break;
		case NasmKey:  state.parsePath(key, val,  ref batConf.nasmCmd); break;
		case VoltaKey: state.parsePath(key, val,  ref batConf.voltaCmd); break;
		default:
			log.info(new "Unknown key '${key}', in file '${state.filename}' ignoring!");
		}
	}
}

fn parseLLVM(ref state: State, table: toml.Value, ref batConf: BatteryConfig)
{
	if (table.type != toml.Value.Type.Table) {
		return log.info(new "Key '${LLVMKey}' is not a array, in file '${state.filename}' ignoring!");
	}

	foreach (key; table.tableKeys()) {
		val := table[key];
		fullKey := new "${LLVMKey}.${key}";

		switch (key) {
		case LLVMArKey:      state.parsePath(fullKey, val, ref batConf.llvmArCmd); break;
		case LLVMWasmLLD:    state.parsePath(fullKey, val, ref batConf.llvmWasmCmd); break;
		case LLVMCKey:       state.parsePath(fullKey, val, ref batConf.llvmC); break;
		case LLVMClangKey:   state.parsePath(fullKey, val, ref batConf.llvmClangCmd); break;
		case LLVMLLDLinkKey: state.parsePath(fullKey, val, ref batConf.llvmLinkCmd); break;
		default:
			log.info(new "Unknown key ${fullKey}, in file '${state.filename}' ignoring!");
		}
	}
}

fn parsePaths(ref state: State, key: string, array: toml.Value, ref pkgs: string[])
{
	if (array.type != toml.Value.Type.Array) {
		return log.info(new "Key '${key}' is not a array, in file '${state.filename}' ignoring!");
	}

	foreach (str; array.array()) {
		if (str.type != toml.Value.Type.String) {
			return log.info(new "Element in '${key}' is not a string, in file '${state.filename}' ignoring!");
		}

		pkgs ~= state.fixupString(str.str());
	}
}

fn parsePath(ref state: State, key: string, val: toml.Value, ref str: string)
{
	if (val.type != toml.Value.Type.String) {
		return log.info(new "Key '${key}' is not a string, in file '${state.filename}' ignoring!");
	}

	path := state.fixupString(val.str());
	if (!path.exists()) {
		log.info(new "Key '${key}' referes to non-existing path '${path}'!");
	}

	str = path;
}

fn fixupString(ref state: State, str: string) string
{
	return fullPath(str.replace("%confdir%", state.path));
}

fn dump(ref batConf: BatteryConfig, message: string)
{
	ss: StringSink;

	ss.sink(message);
	format(ss.sink, "\n\tfilename = '%s'", batConf.filename);
	format(ss.sink, "\n\tvoltaCmd = '%s'", batConf.voltaCmd);
	format(ss.sink, "\n\tnasmCmd = '%s'", batConf.nasmCmd);
	format(ss.sink, "\n\tllvmArCmd = '%s'", batConf.llvmArCmd);
	format(ss.sink, "\n\tllvmClangCmd = '%s'", batConf.llvmClangCmd);
	format(ss.sink, "\n\tllvmLinkCmd = '%s'", batConf.llvmLinkCmd);
	format(ss.sink, "\n\tllvmWasmCmd = '%s'", batConf.llvmWasmCmd);
	format(ss.sink, "\n\tllvmC = %s", batConf.llvmC);
	format(ss.sink, "\n\tpkgs = [");
	foreach (arg; batConf.pkgs) {
		ss.sink("\n\t\t'");
		ss.sink(arg);
		ss.sink("'");
	}
	ss.sink("]");

	log.info(ss.toString());
}
