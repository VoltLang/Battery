module lib.microtar;
extern (C):

import core.c.stdio;
import core.c.stdlib;

enum MTAR_VERSION = "0.1.0";

enum
{
	MTAR_ESUCCESS     =  0,
	MTAR_EFAILURE     = -1,
	MTAR_EOPENFAIL    = -2,
	MTAR_EREADFAIL    = -3,
	MTAR_EWRITEFAIL   = -4,
	MTAR_ESEEKFAIL    = -5,
	MTAR_EBADCHKSUM   = -6,
	MTAR_ENULLRECORD  = -7,
	MTAR_ENOTFOUND    = -8
}

enum
{
	MTAR_TREG   = '0',
	MTAR_TLNK   = '1',
	MTAR_TSYM   = '2',
	MTAR_TCHR   = '3',
	MTAR_TBLK   = '4',
	MTAR_TDIR   = '5',
	MTAR_TFIFO  = '6'
}

struct mtar_header_t
{
	mode, owner, size, mtime, type: u32;
	name: char[100];
	linkname: char[100];
}

struct mtar_t
{
	read: fn(tar: mtar_t*, data: void*, size: u32) i32;
	write: fn(tar: mtar_t*, data: const(void)*, size: u32) i32;
	seek: fn(tar: mtar_t*, pos: u32);
	close: fn(tar: mtar_t*);
	stream: void*;
	pos, remaining_data, last_header: u32;
}

fn mtar_strerror(err: i32) const(char)*;

fn mtar_open(tar: mtar_t*, filename: const(char)*, mode: const(char)*) i32;
fn mtar_close(tar: mtar_t*) i32;

fn mtar_seek(tar: mtar_t*, pos: u32) i32;
fn mtar_rewind(tar: mtar_t*) i32;
fn mtar_next(tar: mtar_t*) i32;
fn mtar_find(tar: mtar_t*, name: const(char)*, h: mtar_header_t*) i32;
fn mtar_read_header(tar: mtar_t*, h: mtar_header_t*) i32;
fn mtar_read_data(tar: mtar_t*, ptr: void*, size: u32) i32;

fn mtar_write_header(tar: mtar_t*, h: const(mtar_header_t)*) i32;
fn mtar_write_file_header(tar: mtar_t*, name: const(char)*, size: u32) i32;
fn mtar_write_dir_header(tar: mtar_t*, name: const(char)*) i32;
fn mtar_write_data(tar: mtar_t*, data: const(void)*, size: u32) i32;
fn mtar_finalize(tar: mtar_t*) i32;
