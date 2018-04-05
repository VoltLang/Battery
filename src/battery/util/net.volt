module battery.util.net;

import io   = watt.io;
import http = watt.http;
import conv = watt.conv;
import path = [watt.path, watt.text.path];
import text = watt.text.string;
import file = watt.io.file;

import interfaces = battery.interfaces;
import config     = battery.configuration;
import extract    = battery.util.extract;
import github     = battery.util.github;
import scanner    = battery.frontend.scanner;
import params     = battery.frontend.parameters;

enum ProgressBarLength = 30;
enum SrcDir     = ".battery${path.dirSeparator}src";
enum ToolDir    = ".battery${path.dirSeparator}tools";

enum NasmExe   = "nasm.exe";
enum ClangExe  = "clang.exe";

/*!
 * Download what was needed for --netboot parameter.
 */
fn boot(drv: interfaces.Driver, cfg: config.Configuration, arg: params.ArgParser)
{
	downloadDependency(drv, cfg, arg, "volta");
	toolPath := downloadTool("volta");
	if (toolPath !is null) {
		drv.addCmd(false, "volta", toolPath);
	}

	toolchainArchive := github.downloadLatestReleaseFile("VoltLang", "Toolchain", "toolchain-win-x86_64.zip");
	toolchainDir     := path.dirName(toolchainArchive);
	extract.archive(toolchainArchive, toolchainDir);
	file.remove(toolchainArchive);

	nasmPath := path.concatenatePath(toolchainDir, NasmExe);
	if (file.exists(nasmPath)) {
		drv.addCmd(false, "nasm", nasmPath);
	}

	clangPath := path.concatenatePath(toolchainDir, ClangExe);
	if (file.exists(clangPath)) {
		drv.addCmd(false, "clang", clangPath);
	}
}

fn downloadTool(name: string) string
{
	// @todo Merge what we can with the downloadDependency(string) code.
	name = conv.toLower(name);
	downloadDir := path.concatenatePath(ToolDir, name);
	path.mkdirP(downloadDir);
	archiveFilename, exeName: string;
	io.writeln(new "Downloading tool executable ${name}");
	switch (name) {
	case "volta":
		archiveFilename = downloadSource(server:`www.github.com`, url:`VoltLang/Volta/releases/download/v0.1.0-alpha/volta-0.1.0-msvc64.zip`, useHttps: true);
		exeName = "volta.exe";
		break;
	default:
		break;
	}
	if (archiveFilename is null) {
		return null;
	}
	extract.archive(archiveFilename, downloadDir);
	finalPath := path.concatenatePath(downloadDir, exeName);
	if (!file.exists(finalPath)) {
		io.writeln(new "Couldn't download tool '${name}'"); io.output.flush();
		return null;
	}
	return finalPath;
}

fn downloadDependency(drv: interfaces.Driver, cfg: config.Configuration, arg: params.ArgParser, name: string) interfaces.Project
{
	extractedPath := downloadDependency(name);
	if (extractedPath !is null) {
		p := scanner.scanDir(drv, cfg, extractedPath);
		arg.process(cfg, p);
		if (auto lib = cast(interfaces.Lib)p) {
			drv.add(lib);
		} else if (auto exe = cast(interfaces.Exe)p) {
			drv.add(exe);
		}
		return p;
	}
	return null;
}

/*!
 * Download and extract a dependency.
 *
 * @Returns The path to the extracted dependency
 * or `null` on failure.
 */
fn downloadDependency(name: string) string
{
	name = conv.toLower(name);
	downloadDir := path.concatenatePath(SrcDir, name);
	path.mkdirP(downloadDir);
	archiveFilename: string;
	io.writeln(new "Downloading ${name}");
	switch (name) {
	case "watt":
		archiveFilename = downloadSource(server:`www.github.com`, url:`/VoltLang/Watt/archive/master.zip`, useHttps:true);
		break;
	case "volta":
		archiveFilename = downloadSource(server:`www.github.com`, url:`/VoltLang/Volta/archive/master.zip`, useHttps:true);
		break;
	default:
		break;
	}
	if (archiveFilename is null) {
		return null;
	}
	extractedPath := extract.archive(archiveFilename, downloadDir);
	if (extractedPath !is null) {
		io.writeln(new "Extracted to '${extractedPath}'"); io.output.flush();
	} else {
		io.writeln(new "Failed to extract '${archiveFilename}'"); io.output.flush();
	}
	return extractedPath;
}

fn downloadSource(server: string, url: string, useHttps: bool) string
{
	return download(server, url, useHttps, SrcDir);
}

fn download(server: string, url: string, useHttps: bool, destinationDirectory: string) string
{
	components := text.split(url, '/');
	if (components.length == 0) {
		return null;
	}
	filename := path.concatenatePath(destinationDirectory, components[$-1]);
	h   := new http.Http();
	req := new http.Request(h);
	req.server = server;
	req.url = url;
	req.port = useHttps ? 443 : 80;
	req.secure = useHttps;

	fn progressBar()
	{
		if (req.contentLength() == 0) {
			io.write(new "${req.bytesDownloaded()} bytes\r");
			io.output.flush();
			return;
		}
		downloaded := cast(f64)req.bytesDownloaded();
		maximum    := cast(f64)req.contentLength();
		ratio      := (downloaded / maximum);
		pips       := cast(i32)(ProgressBarLength * ratio);
		spaces     := ProgressBarLength - pips;
		io.write("[");
		foreach (i; 0 .. pips) {
			io.write("#");
		}
		foreach (i; 0 .. spaces) {
			io.write(" ");
		}
		io.write(new "] ${cast(i32)(ratio * 100)}%\r");
		io.output.flush();
	}

	h.loop(progressBar);
	io.output.writeln("");
	if (req.errorGenerated()) {
		io.error.writeln(new "Download failed: ${req.errorString()}");
		return null;
	} else {
		file.write(req.getData(), filename);
		io.writeln(new "Downloaded ${filename}");
		return filename;
	}
}
