// Copyright © 2012-2016, Jakob Bornecrantz.  All rights reserved.
// See copyright notice in src/battery/license.d (BOOST ver. 1.0).
module uni.util.cmd;

import core.stdc.stdio : FILE, fileno, stdin, stdout, stderr;
import core.exception;

version(Windows) {
	import core.windows.windows;
}

import watt.conv;
import watt.process;


/**
 * Helper class to launch one or more processes
 * to run along side the main process.
 */
class CmdGroup
{
public:
	alias DoneDg = dg (int);  // Is called with the retval of the completed command.

private:
	cmdStore: Cmd[];

	/// Environment to launch all processes in.
	env: Environment;

	/// For Windows waitOne, to avoid unneeded allocations.
	version (Windows) __handles: Pid.NativeID[];

	/// Number of simultanious jobs.
	maxWaiting: uint;

	/// Number of running jobs at this moment.
	waiting: uint;

	/**
	 * Small container representing a executed command, is recycled.
	 */
	static class Cmd
	{
	public:
		/// Executable.
		cmd: string;

		/// Arguments to be passed.
		args: string[];

		/// Called when command has completed.
		done: DoneDg;

		/// System specific process handle.
		handle: Pid.NativeID;

		/// In use.
		used: bool;


	public:
		/**
		 * Initialize all the fields.
		 */
		fn set(cmd: string, args: string[], dgt: DoneDg,
		       handle: Pid.NativeID)
		{
			used = true;
			this.cmd = cmd;
			this.args = args;
			this.done = dgt;
			this.handle = handle;
		}

		/**
		 * Reset to a unused state.
		 */
		fn reset()
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
	this(env: Environment, maxWaiting: uint)
	{
		this.env = env;
		this.maxWaiting = maxWaiting;

		cmdStore = new Cmd[](maxWaiting);
		version (Windows) __handles = new Pid.NativeID[](maxWaiting);

		foreach (ref cmd; cmdStore) {
			cmd = new Cmd();
		}
	}

	fn run(cmd: string, args: string[], dgt: DoneDg, log: FILE*)
	{
		count : int;
		while (waiting >= maxWaiting) {
			waitOne();
			if (count++ > 5) {
				throw new Exception("Wait one failed to many times");
			}
		}

		pid := spawnProcess(cmd, args, null, log, log, env);

		version (Windows) {

			newCmd(cmd, args, dgt, pid._handle);
			waiting++;

		} else version(Posix) {

			newCmd(cmd, args, dgt, pid._pid);
			waiting++;

		} else {
			static assert(false);
		}
	}

	fn waitOne()
	{
		version(Windows) {
			hCount : uint;
			foreach (cmd; cmdStore) {
				if (cmd.used) {
					__handles[hCount++] = cmd.handle;
				}
			}
			ptr := __handles.ptr;
			uRet := WaitForMultipleObjects(hCount, ptr, FALSE, cast(uint)-1);
			if (uRet == cast(DWORD)-1 || uRet >= hCount) {
				throw new Exception("Wait failed with error code " ~ .toString(cast(int)GetLastError()));
			}

			hProcess := __handles[uRet];

			// Retrieve the command for the returned wait, and remove it from the lists.
			c: Cmd;
			foreach (cmd; cmdStore) {
				if (hProcess !is cmd.handle) {
					continue;
				}
				c = cmd;
				break;
			}

			result: int = -1;
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

			c: Cmd;
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

		// But also reset it before calling the dgt
		dgt := c.done;

		c.reset();
		waiting--;

		if ((dgt !is null)) {
			dgt(result);
		}
	}

	fn waitAll()
	{
		while(waiting > 0) {
			waitOne();
		}
	}

private:
	fn newCmd(cmd: string, args: string[], dgt: DoneDg, handle: Pid.NativeID) Cmd
	{
		foreach (c; cmdStore) {
			if (c is null) {
				throw new Exception("null cmdStore.");
			}
			if (!c.used) {
				c.set(cmd, args, dgt, handle);
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
	this(cmd: string, reason: string)
	{
		err := format("The below command failed due to: %s\n%s", reason, cmd);
		super(err);
	}

	this(cmd: string, args: string[], reason: string)
	{
		err := format("The below command failed due to: %s\n%s %s", reason, cmd, args);
		super(err);
	}

	this(cmd: string, result: int)
	{
		err := format("The below command returned: %s\n%s", result, cmd);
		super(err);
	}

	this(cmd: string, args: string[], result: int)
	{
		err := format("The below command returned: %s\n%s %s", result, cmd, args);
		super(err);
	}
}
