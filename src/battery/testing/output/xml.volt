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

	fprintf(f, "<testsuites errors=\"%u\" failures=\"%u\" tests=\"%u\">\n",
	        fail, xfail, total);

	foreach (test; tests) {
		final switch(test.result) with (Result) {
		case PASS, XPASS: printXmlOk(f, test); break;
		case FAIL, XFAIL: printXmlBad(f, test); break;
		}
	}

	fprintf(f, "</testsuites>\n".ptr);
	fflush(f);
	fclose(f);
}


private:

fn printXmlOk(f: FILE*, test: Test)
{
	name := test.name;
	pfix := test.prefix;
	outputStr := test.getOutput();
	errorStr := test.getError();

	if (outputStr.length == 0 && errorStr.length == 0) {
		fprintf(f, "\t<testcase classname=\"%.*s%.*s\" name=\"\"/>\n".ptr,
			cast(i32)pfix.length, pfix.ptr, cast(int)name.length, name.ptr);
	} else {
		fprintf(f, "\t<testcase classname=\"%.*s%.*s\" name=\"\">\n".ptr,
			cast(i32)pfix.length, pfix.ptr, cast(int)name.length, name.ptr);
		printOutput(f, test);
		fprintf(f, "\t</testcase>\n");
	}
}

fn printXmlBad(f: FILE*, test: Test)
{
	name := test.name;
	msg := test.msg;
	pfix := test.prefix;

	fprintf(f, "\t<testcase classname=\"%.*s%.*s\" name=\"\">\n".ptr,
	        cast(i32)pfix.length, pfix.ptr, cast(int)name.length, name.ptr);
	fprintf(f, "\t\t<failure type=\"Error\">%.*s</failure>\n".ptr,
	        cast(int)msg.length, msg.ptr);
	printOutput(f, test);
	fprintf(f, "\t</testcase>\n".ptr);
}

fn printOutput(f: FILE*, test: Test)
{
	fn print(str: scope const(char)[]) {
		fprintf(f, "%.*s", cast(i32)str.length, str.ptr);
	}

	outputStr := test.getOutput();
	if (outputStr.length > 0) {
		print("\t\t<system-out>");
		htmlEscape(print, outputStr);
		print("\t\t</system-out>\n");
	}
	errorStr := test.getError();
	if (errorStr.length > 0) {
		print("\t\t<system-out>");
		htmlEscape(print, errorStr);
		print("\t\t</system-out>\n");
	}
}
