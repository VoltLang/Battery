// Copyright © 2012-2016, Jakob Bornecrantz.  All rights reserved.
// See copyright notice in src/tesla/license.volt (BOOST ver. 1.0).
module battery.testing.output.xml;

import core.c.stdio : FILE, fprintf, fopen, fflush, fclose;
import watt.text.format : format;
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
		if (test.result == Result.SKIPPED) {
			continue;
		}
		total++;
		final switch(test.result) with (Result) {
		case FAIL: fail++; break;
		case XFAIL: xfail++; break;
		case PASS, XPASS: break;
		case SKIPPED: assert(false);
		}
	}

	fn print(str: scope const(char)[]) {
		fprintf(f, "%.*s", cast(i32)str.length, str.ptr);
	}

	print("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n");
	format(print, "<testsuites errors=\"%s\" failures=\"%s\" tests=\"%s\">\n",
	        fail, xfail, total);
	format(print, "\t<testsuite name=\"%s\" errors=\"%s\" failures=\"%s\" tests=\"%s\">\n",
	        ident, fail, xfail, total);

	foreach (test; tests) {
		final switch(test.result) with (Result) {
		case PASS, XPASS: printXmlOk(print, ident, test); break;
		case FAIL, XFAIL: printXmlBad(print, ident, test); break;
		case SKIPPED: break;
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

fn printXmlOk(print: Sink, ident: string, test: Test)
{
	outputStr := test.getOutput();
	errorStr := test.getError();

	stopTag := outputStr.length == 0 && errorStr.length == 0;

	printTestCase(print, ident, test, stopTag);

	if (!stopTag) {
		printOutput(print, test);
		print("\t\t</testcase>\n");
	}
}

fn printXmlBad(print: Sink, ident: string, test: Test)
{
	printTestCase(print, ident, test, false);
	print("\t\t<failure message=\"");
	htmlEscape(print, test.msg);
	print("\" type=\"Error\"></failure>\n");
	printOutput(print, test);
	print("\t\t</testcase>\n");
}

fn printTestCase(print: Sink, ident: string, test: Test, stopTag: bool)
{
	format(print, "\t\t<testcase classname=\"%s/%s\" name=\"%s\"",
		ident, test.project.name, test.name);

	if (stopTag) {
		print("/>\n");
	} else {
		print(">\n");
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
