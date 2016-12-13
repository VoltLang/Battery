// Copyright © 2012-2016, Jakob Bornecrantz.  All rights reserved.
// See copyright notice in src/tesla/license.volt (BOOST ver. 1.0).
module battery.testing.output.xml;

import core.stdc.stdio : FILE, fprintf, fopen, fflush, fclose;
import watt.text.sink : Sink;
import watt.conv : toStringz;
import watt.text.html : htmlEscape;
import battery.testing.test;


fn writeXmlFile(ident: string, filename: string, tests: Test[])
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
	fprintf(f, "\t<testsuite name=\"%.*s\" errors=\"%u\" failures=\"%u\" tests=\"%u\">\n",
	        cast(int)ident.length, ident.ptr, fail, xfail, total);

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

	outputStr := test.getOutput();
	errorStr := test.getError();

	stopTag := outputStr.length == 0 && errorStr.length == 0;

	printTestCase(print, test, stopTag);

	if (!stopTag) {
		printOutput(print, test);
		fprintf(f, "\t\t</testcase>\n");
	}
}

fn printXmlBad(f: FILE*, test: Test)
{
	fn print(str: scope const(char)[]) {
		fprintf(f, "%.*s", cast(i32)str.length, str.ptr);
	}

	msg := test.msg;

	printTestCase(print, test, false);
	print("\t\t<failure message=\"");
	htmlEscape(print, msg);
	print("\" type=\"Error\"></failure>\n");
	printOutput(print, test);
	print("\t\t</testcase>\n");
}

fn printTestCase(print: Sink, test: Test, stopTag: bool)
{
	print("\t\t<testcase classname=\"");
	print(test.project.name);
	print("\" name=\"");
	print(test.name);

	if (stopTag) {
		print("\"/>\n");
	} else {
		print("\">\n");
	}
}

fn printOutput(print: Sink, test: Test)
{
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
