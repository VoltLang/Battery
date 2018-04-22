// Copyright © 2016-2017, Jakob Bornecrantz.  All rights reserved.
// See copyright notice in src/battery/license.volt (BOOST ver. 1.0).
/*!
 * Holds code for interacting with github.
 */
module battery.util.github;

import io = watt.io;
import file = watt.io.file;
import json = watt.json;
import http = watt.http;
import text = watt.text.string;
import semver = watt.text.semver;
import path = [watt.path, watt.text.path];

import battery.interfaces;
import net = battery.util.net;


class Repo
{
	original: string;
	org: string;
	proj: string;
}

fn parseUrl(drv: Driver, url: string) Repo
{
	// Strip any whitespace.
	// >github.com/Org/Proj<
	url = text.strip(url);
	original := url;

	// Remove the prefix.
	// >github.com/<Org/Proj
	if (!text.startsWith(url, Prefix)) {
		drv.abort("Doesn't start with prefix '%s'", original);
		return null;
	}
	url = url[Prefix.length .. $];


	// Find the first slash.
	// githun.com/Org>/<Proj
	slashIndex := text.indexOf(url, '/');

	// Org name needs to be at least one character.
	if (slashIndex < 1) {
		drv.abort("no slash found '%s'", original);
		return null;
	}

	// We have the organization.
	// github.com/>Org</Proj
	org := url[0 .. slashIndex];

	// Need to be at least one character in project name.
	// (one for / and one for the character).
	// github.com/Org/>Proj<
	if (cast(size_t)slashIndex + 2 >= url.length) {
		drv.abort("not enough characters for project name '%s'", original);
		return null;
	}
	proj := url[slashIndex + 1 .. $];

	repo := new Repo();
	repo.original = original;
	repo.org = org;
	repo.proj = proj;

	return repo;
}

/*!
 * Download the source zip from a GitHub project's latest release.
 *
 * Get the latest release from `owner/repo`'s source, download it
 * and return the path, or return `null` on failure.
 */
fn downloadLatestSource(owner: string, repo: string) string
{
	latestReleaseJson := apiGetLatestReleaseJson(owner, repo);
	if (latestReleaseJson is null) {
		return null;
	}
	jsonRoot := json.parse(latestReleaseJson);
	tag      := tagName(jsonRoot);
	if (tag is null) {
		return null;
	}
	zipUrl   := sourceZip(jsonRoot);
	if (zipUrl is null) {
		return null;
	}

	newName := new "${owner}${repo}_${tag}.zip";
	existingPath := path.concatenatePath(net.SrcDir, newName);
	if (file.exists(existingPath)) {
		io.writeln(new "Using existing file ${newName}");
		io.output.flush();
		return existingPath;
	}

	zipFile := downloadSourceZip(zipUrl);
	if (zipFile is null) {
		return null;
	}
	file.rename(zipFile, existingPath);
	return existingPath;
}

/*!
 * Download a file from a GitHub project's latest release.
 *
 * If the latest release from `owner/repo` contains a release asset with a 
 * name ending in `targetEnd`, download it and return the path to the downloaded
 * file. Otherwise, return `null`.
 */
fn downloadLatestReleaseFile(owner: string, repo: string, targetEnd: string) string
{
	latestReleaseJson   := apiGetLatestReleaseJson(owner, repo);
	if (latestReleaseJson is null) {
		return null;
	}
	jsonRoot      := json.parse(latestReleaseJson);
	latestRelease := filterReleaseAssets(jsonRoot, targetEnd);
	if (latestRelease is null) {
		return null;
	}
	existingPath := alreadyDownloaded(latestRelease, owner, repo);
	if (existingPath !is null) {
		sz := file.size(existingPath);
		if (sz == latestRelease.size) {
			return existingPath;
		}
		io.writeln(new "Skipping '${latestRelease.filename}', as file size does not match.");
		io.output.flush();
	}
	return downloadRelease(latestRelease.url, owner, repo);
}

//! Get the latest release JSON for a given project, or `null` on failure.
fn apiGetLatestReleaseJson(owner: string, repo: string) string
{
	h := new http.Http();
	r := new http.Request(h);
	r.server = "api.github.com";
	r.url    = new "/repos/${owner}/${repo}/releases/latest";
	r.port   = 443;
	r.secure = true;
	h.loop();
	if (r.errorGenerated()) {
		return null;
	}
	return r.getString();
}

fn downloadSourceZip(url: string) string
{
	prefix := "https://api.github.com";
	if (!text.startsWith(url, prefix)) {
		return null;
	}
	url = url[prefix.length .. $];
	return net.downloadSource("api.github.com", url, true);
}

/*!
 * Given a JSON root associated with the latest release, get the source zip.
 *
 * @Returns The URL for the zip, or `null`.
 */
fn sourceZip(root: json.Value) string
{
	if (!root.hasObjectKey("zipball_url")) {
		return null;
	}
	zipballUrl := root.lookupObjectKey("zipball_url");
	if (zipballUrl.type() != json.DomType.STRING) {
		return null;
	}
	return zipballUrl.str();
}

/*!
 * Given a JSON root associated with the latest release, get the tag.
 *
 * @Returns The tag, or `null`.
 */
fn tagName(root: json.Value) string
{
	if (!root.hasObjectKey("tag_name")) {
		return null;
	}
	tagNameVal := root.lookupObjectKey("tag_name");
	if (tagNameVal.type() != json.DomType.STRING) {
		return null;
	}
	return tagNameVal.str();
}

class Release
{
public:
	this(filename: string, url: string, size: size_t)
	{
		this.filename = filename;
		this.url = url;
		this.size = size;
	}

public:
	filename: string;
	url: string;
	size: size_t;
}

//! If the release JSON `root` has an asset ending in `targetEnd`, return its URL, or `null` otherwise.
fn filterReleaseAssets(root: json.Value, targetEnd: string) Release
{
	// Get the assets.
	if (!root.hasObjectKey("assets")) {
		return null;
	}
	assetsArrayVal := root.lookupObjectKey("assets");
	if (assetsArrayVal.type() != json.DomType.ARRAY) {
		return null;
	}

	// Go through the assets and look for our target.
	assetsArray := assetsArrayVal.array();
	foreach (assetRoot; assetsArray) {
		if (!assetRoot.hasObjectKey("name")) {
			continue;
		}
		name := assetRoot.lookupObjectKey("name");
		if (name.type() != json.DomType.STRING || !text.endsWith(name.str(), targetEnd)) {
			continue;
		}

		if (!assetRoot.hasObjectKey("browser_download_url")) {
			return null;
		}
		url := assetRoot.lookupObjectKey("browser_download_url");
		if (url.type() != json.DomType.STRING) {
			return null;
		}

		if (!assetRoot.hasObjectKey("size")) {
			return null;
		}
		sz := assetRoot.lookupObjectKey("size");
		if (sz.type() != json.DomType.LONG) {
			continue;
		}

		return new Release(name.str(), url.str(), cast(size_t)sz.integer());
	}
	return null;
}

//! If the given Release file is already downloaded, return the path, or `null` otherwise.
fn alreadyDownloaded(rel: Release, owner: string, repo: string) string
{
	destination := path.concatenatePath(net.ToolDir, new "github/${owner}/${repo}");
	destination  = path.concatenatePath(destination, rel.filename);
	if (file.exists(destination)) {
		io.writeln(new "Using existing file '${destination}'");
		io.output.flush();
		return destination;
	}
	return null;
}

//! Download the file at `url` to the tools dir, and return the path, or `null` otherwise.
fn downloadRelease(url: string, owner: string, repo: string) string
{
	if (url is null) {
		return null;
	}
	destination := path.concatenatePath(net.ToolDir, new "github/${owner}/${repo}");
	path.mkdirP(destination);
	prefix := "https://github.com";
	if (!text.startsWith(url, prefix)) {
		return null;
	}
	theUrl := url[prefix.length .. $];
	return net.download(server:`github.com`, url:cast(string)theUrl, useHttps:true, destinationDirectory:destination);
}

private:

enum Prefix = "github.com/";
