// Copyright © 2012-2016, Jakob Bornecrantz.  All rights reserved.
// See copyright notice in src/battery/license.d (BOOST ver. 1.0).
module uni.util.cmd;

import watt.conv;
import watt.process;

version (Windows) {
	import core.windows.windows;
	alias ProcessHandle = HANDLE;
} else {
	import core.posix.sys.types : pid_t;
	alias ProcessHandle = pid_t;
}
import core.stdc.stdio : FILE, fileno, stdin, stdout, stderr;


/**
 * Helper class to launch one or more processes
 * to run along side the main process.
 */
class CmdGroup
{
public:
	alias DoneDg = void delegate(int);  // Is called with the retval of the completed command.

private:
	Cmd[] cmdStore;

	/// For Windows waitOne, to avoid unneeded allocations.
	version (Windows) ProcessHandle[] __handles;

	/// Number of simultanious jobs.
	uint maxWaiting;

	/// Number of running jobs at this moment.
	uint waiting;

	/**
	 * Small container representing a executed command, is recycled.
	 */
	class Cmd
	{
	public:
		/// Executable.
		string cmd;

		/// Arguments to be passed.
		string[] args;

		/// Called when command has completed.
		DoneDg done;

		/// System specific process handle.
		ProcessHandle handle;

		/// In use.
		bool used;


	public:
		/**
		 * Initialize all the fields.
		 */
		void set(string cmd, string[] args, DoneDg dg, ProcessHandle handle)
		{
			used = true;
			this.cmd = cmd;
			this.args = args;
			this.done = dg;
			this.handle = handle;
		}

		/**
		 * Reset to a unused state.
		 */
		void reset()
		{
			used = false;
			cmd = null;
			args = null;
			done = null;
			version (Windows) {
				handle = null;
			} else {
				handle = 0;
			}
		}
	}

public:
	this(uint maxWaiting)
	{
		waiting = 0;
		this.maxWaiting = maxWaiting;
		cmdStore = new Cmd[](maxWaiting);
		version (Windows) __handles = new ProcessHandle[](maxWaiting);

		foreach (ref cmd; cmdStore) {
			cmd = new Cmd();
		}
	}

	void run(string cmd, string[] args, DoneDg dg, FILE* log)
	{
		count : int;
		while (waiting >= maxWaiting) {
			waitOne();
			if (count++ > 5) {
				throw new Exception("Wait one failed to many times");
			}
		}
		pid := spawnProcess(cmd, args, null, log, log);

		version (Windows) {

			newCmd(cmd, args, dg, pid._handle);
			waiting++;

		} else version(Posix) {

			newCmd(cmd, args, dg, pid._pid);
			waiting++;

		} else {
			static assert(false);
		}
	}

	void waitOne()
	{
		version(Windows) {
			hCount : uint;
			foreach (cmd; cmdStore) {
				if (cmd.used) {
					__handles[hCount++] = cmd.handle;
				}
			}
			ptr := cast(HANDLE*)__handles.ptr;
			uRet := WaitForMultipleObjects(hCount, ptr, FALSE, cast(uint)-1);
			if (uRet == cast(DWORD)-1 || uRet >= hCount) {
				throw new Exception("Wait failed with error code " ~ .toString(cast(int)GetLastError()));
			}

			hProcess := cast(HANDLE)__handles[uRet];

			// Retrieve the command for the returned wait, and remove it from the lists.
			Cmd c;
			foreach (cmd; cmdStore) {
				if (hProcess !is cmd.handle) {
					continue;
				}
				c = cmd;
				break;
			}

			int result = -1;
			bRet := GetExitCodeProcess(hProcess, cast(uint*)&result);
			cRet := CloseHandle(hProcess);
			if (bRet == 0) {
				c.reset();
				throw new CmdException(c.cmd, c.args,
					"abnormal application termination");
			}
			if (cRet == 0) {
				throw new Exception("CloseHandle failed with error code " ~ .toString(cast(int)GetLastError()));
			}

		} else version(Posix) {

			result : int;
			pid : pid_t;

			if (waiting == 0) {
				return;
			}

			Cmd c;
			// Because stopped processes doesn't count.
			while(true) {
				result = waitManyPosix(out pid);

				foundPid : bool;
				foreach (cmd; cmdStore) {
					if (cmd.handle != pid) {
						continue;
					}

					c = cmd;
					foundPid = true;
					break;
				}

				if (foundPid) {
					break;
				}

				if (pid > 0) {
					throw new Exception("PID waited on but not cleared!\n");
				}
				continue;
			}
		} else {
			static assert(false);
		}

		// But also reset it before calling the dg
		dg := c.done;

		c.reset();
		waiting--;

		if ((dg !is null)) {
			dg(result);
		}
	}

	void waitAll()
	{
		while(waiting > 0) {
			waitOne();
		}
	}

private:
	Cmd newCmd(string cmd, string[] args, DoneDg dg, ProcessHandle handle)
	{
		foreach (c; cmdStore) {
			if (c is null) {
				throw new Exception("null cmdStore.");
			}
			if (!c.used) {
				c.set(cmd, args, dg, handle);
				return c;
			}
		}
		throw new Exception("newCmd failure");
	}
}

/**
 * Exception form and when execquting commands.
 */
class CmdException : Exception
{
	this(string cmd, string reason)
	{
		super("The below command failed due to: " ~ reason ~ "\n" ~ cmd);
	}

	this(string cmd, string[] args, string reason)
	{
		foreach (a; args) {
			cmd ~= " " ~ a;
		}
		this(cmd, reason);
	}

	this(string cmd, int result)
	{
		super("The below command returned: " ~ .toString(result) ~ " \n" ~ cmd);
	}

	this(string cmd, string[] args, int result)
	{
		foreach (a; args) {
			cmd ~= " " ~ a;
		}
		this(cmd, result);
	}
}
