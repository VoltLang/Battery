// Copyright © 2012-2016, Jakob Bornecrantz.  All rights reserved.
// See copyright notice in src/tesla/license.volt (BOOST ver. 1.0).
module battery.testing.output.xml;

import core.stdc.stdio : FILE, fprintf, fopen, fflush, fclose;
import watt.conv : toStringz;
import watt.text.html : htmlEscape;
import battery.testing.test;


fn writeXmlFile(filename: string, tests: Test[])
{
	f := fopen(toStringz(filename), "w+");
	if (f is null) {
		return;
	}

	total, fail, xfail: int;
	foreach (test; tests) {
		total++;
		final switch(test.result) with (Result) {
		case FAIL: fail++; break;
		case XFAIL: xfail++; break;
		case PASS, XPASS: break;
		}
	}

	fprintf(f, "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n".ptr);
	fprintf(f, "<testsuites errors=\"%u\" failures=\"%u\" tests=\"%u\">\n",
	        fail, xfail, total);
	fprintf(f, "\t<testsuite errors=\"%u\" failures=\"%u\" tests=\"%u\">\n",
	        fail, xfail, total);

	foreach (test; tests) {
		final switch(test.result) with (Result) {
		case PASS, XPASS: printXmlOk(f, test); break;
		case FAIL, XFAIL: printXmlBad(f, test); break;
		}
	}

	fprintf(f, "\t\t<system-out/>\n".ptr);
	fprintf(f, "\t\t<system-err/>\n".ptr);
	fprintf(f, "\t</testsuite>\n".ptr);
	fprintf(f, "</testsuites>\n".ptr);
	fflush(f);
	fclose(f);
}


private:

fn printXmlOk(f: FILE*, test: Test)
{
	fn print(str: scope const(char)[]) {
		fprintf(f, "%.*s", cast(i32)str.length, str.ptr);
	}

	name := test.name;
	pfix := test.prefix;
	outputStr := test.getOutput();
	errorStr := test.getError();

	print("\t\t<testcase classname=\"");
	print(pfix);
	print(name);
	print("\" name=\"\"");

	if (outputStr.length == 0 && errorStr.length == 0) {
		print("/>\n");
	} else {
		print(">\n");
		printOutput(f, test);
		fprintf(f, "\t\t</testcase>\n");
	}
}

fn printXmlBad(f: FILE*, test: Test)
{
	fn print(str: scope const(char)[]) {
		fprintf(f, "%.*s", cast(i32)str.length, str.ptr);
	}

	name := test.name;
	msg := test.msg;
	pfix := test.prefix;

	print("\t\t<testcase classname=\"");
	print(pfix);
	print(name);
	print("\" name=\"\">\n");

	print("\t\t<failure message=\"");
	htmlEscape(print, msg);
	print("\" type=\"Error\"></failure>\n");
	printOutput(f, test);
	print("\t\t</testcase>\n");
}

fn printOutput(f: FILE*, test: Test)
{
	fn print(str: scope const(char)[]) {
		fprintf(f, "%.*s", cast(i32)str.length, str.ptr);
	}

	outputStr := test.getOutput();
	if (outputStr.length > 0) {
		print("\t\t\t<system-out>");
		htmlEscape(print, outputStr);
		print("\t\t\t</system-out>\n");
	}
	errorStr := test.getError();
	if (errorStr.length > 0) {
		print("\t\t\t<system-err>");
		htmlEscape(print, errorStr);
		print("\t\t\t</system-err>\n");
	}
}
