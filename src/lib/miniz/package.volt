module lib.miniz;
extern (C):

import core.c.config;
import core.c.time;
import core.c.stdio;

alias MZ_FILE = FILE;

alias mz_ulong = c_ulong;

fn mz_free(p: void*);

enum MZ_ADLER32_INIT = 1;
fn mz_adler32(adler: mz_ulong, ptr: u8*, buf_len: size_t) mz_ulong;

enum MZ_CRC32_INIT = 0;
fn mz_crc32(crc: mz_ulong, ptr: u8*, buf_len: size_t) mz_ulong;

enum
{
	MZ_DEFAULT_STRATEGY = 0,
	MZ_FILTERED = 1,
	MZ_HUFFMAN_ONLY = 2,
	MZ_RLE = 3,
	MZ_FIXED = 4
}

enum MZ_DEFLATED = 8;

alias mz_alloc_func   = fn(opaque: void*, items: size_t, size: size_t) void*;
alias mz_free_func    = fn(opaque: void*, address: void*);
alias mz_realloc_func = fn(opaque: void*, address: void*, items: size_t, size: size_t);

enum MZ_VERSION         = "10.0.2";
enum MZ_VERNUM          = 0xA020;
enum MZ_VER_MAJOR       = 10;
enum MZ_VER_MINOR       = 0;
enum MZ_VER_REVISION    = 2;
enum MZ_VER_SUBREVISION = 0;

/*!
 * Flush values.  
 * For typical usage you only need MZ_NO_FLUSH and MZ_FINISH.
 */
enum
{
	MZ_NO_FLUSH = 0,
	MZ_PARTIAL_FLUSH = 1,
	MZ_SYNC_FLUSH = 2,
	MZ_FULL_FLUSH = 3,
	MZ_FINISH = 4,
	MZ_BLOCK = 5
}

/*!
 * Return status codes.
 */
enum
{
	MZ_OK = 0,
	MZ_STREAM_END = 1,
	MZ_NEED_DICT = 2,
	MZ_ERRNO = -1,
	MZ_STREAM_ERROR = -2,
	MZ_DATA_ERROR = -3,
	MZ_MEM_ERROR = -4,
	MZ_BUF_ERROR = -5,
	MZ_VERSION_ERROR = -6,
	MZ_PARAM_ERROR = -10000
}

/*!
 * Compression levels.  
 * 0-9 are the standard zlib-style levels,
 * 10 is best possible compression.
 * MZ_DEFEAULT_COMPRESSION=MZ_DEFAULT_LEVEL
 */
enum
{
	MZ_NO_COMPRESSION = 0,
	MZ_BEST_SPEED = 1,
	MZ_BEST_COMPRESSION = 9,
	MZ_UBER_COMPRESSION = 10,
	MZ_DEFAULT_LEVEL = 6,
	MZ_DEFAULT_COMPRESSION = -1
}

enum MZ_DEFAULT_WINDOW_BITS = 15;

struct mz_internal_state {}

//! Compression/decompression stream struct.
struct mz_stream_s
{
	//! Pointer to the next byte to read.
	next_in: u8*;
	//! Number of bytes available at `next_in`.
	avail_in: u32;
	//! Total number of bytes consumer so far.
	total_in: mz_ulong;

	//! Pointer to next byte write.
	next_out: u8*;
	//! Number of bytes that can be written to `next_out`.
	avail_out: u32;
	//! Total number of bytes produced so far.
	total_out: mz_ulong;

	//! Error message. (unused)
	msg: char*;
	//! Internal state, allocated by `zalloc` and `zfree`.
	state: mz_internal_state*;

	//! Optional heap allocation function (defaults to `malloc`).
	zalloc: mz_alloc_func;
	//! Optional heap free function (defaults to `free`).
	zfree: mz_free_func;
	//! Heap alloc function user pointer.
	opaque: void*;

	//! Unused.
	data_type: i32;
	//! adler32 of the source or uncompressed data.
	adler: mz_ulong;
	//! Unused.
	reserved: mz_ulong;
}

alias mz_streamp = mz_stream_s*;

//! @Returns the `miniz.c` version string.
fn mz_version() const(char)*;

/*!
 * Initialise a compressor with default options.
 * 
 * `level` must be between [`MZ_NO_COMPRESSION`, `MZ_BEST_COMPRESSION`].
 * Level 1 enables a specially optimised compression function that's been
 * optimised purely for performance, not ratio.
 *
 * @Param pStream Must point to an initialised `mz_stream` struct.
 * @Param level Compression level.
 *
 * @Returns `MZ_OK` on success. `MZ_STREAM_ERROR` if the stream is bogus.
 * `MZ_PARAM_ERROR` if the input parameters are bogus. `MZ_MEM_ERROR` on
 * out of memory.
 */
fn mz_deflateInit(pStream: mz_streamp, level: i32);

/*!
 * Like `mz_deflate`, except with more control.  
 * Additional parameters:
 *   - `method` must be `MZ_DEFLATED`
 *   - `windows_bits` must be `MZ_DEFAULT_WINDOW_BITS` (to wrap
 *   the deflate stream with zlib header/adler-32 footer).
 * `mem_level` must be between [1, 9] (it's checked but ignored by `miniz.c`).
 */
fn mz_deflateInit2(pStream: mz_streamp, level: i32, method: i32,
	windows_bits: i32, mem_level: i32, strategy: i32) i32;

/*!
 * Quickly resets a compressor without having to reallocate anything.  
 * Same as calling `mz_deflateEnd` followed by `mz_deflateInit`/`mz_deflateInit2`.
 */
fn mz_deflateReset(pStream: mz_streamp) i32;

/*!
 * Compresses the input to output, consuming as much of the input
 * and producing as much output as possible.
 *
 * @Param pStream The stream to read from and write to. You must initialise/update
 * the `next_in`, `avail_in`, `next_out`, and `avail_out` members.
 * @Param flush May be `MZ_NO_FLUSH`, `MZ_PARTIAL_FLUSH`, `MZ_SYNC_FLUSH`,
 * `MZ_FULL_FLUSH`, or `MZ_FINISH`.
 * @Returns `MZ_OK` on success (when flushing, or if more input is needed but
 * not available, and/or there's more output to be written but the output
 * buffer is full). `MZ_STREAM_END` if all input has been consumed and all output
 * bytes have been written. Don't call `mz_deflate` on the stream anymore.
 * `MZ_STREAM_ERROR` if the stream is bogus. `MZ_PARAM_ERROR` if one of the parameters
 * is invalid. `MZ_BUF_ERROR` if no forward progress is possible because the input
 * and/or output buffers are empty. (Fill up the input buffer or free up some output
 * space and try again). 
 */
fn mz_deflate(pStream: mz_streamp, flush: i32) i32;

/*!
 * Deinitialise a compressor.
 * @Returns `MZ_OK` on success. `MZ_STREAM_ERROR` if the stream is bogus.
 */
fn mz_deflateEnd(pStream: mz_streamp) i32;

/*!
 * @Returns A (very) conservative upper bound on the amount of data that could
 * be generated by `deflate`, assuming flush is set to only `MZ_NO_FLUSH` or
 * `MZ_FINISH`.
 */
fn mz_deflateBound(pStream: mz_streamp, source_len: mz_ulong) mz_ulong;

/*!
 * Single-call compression functions `mz_compress` and `mz_compress2`.
 * @Returns `MZ_OK` on success, or one of the error codes from `mz_deflate` on failure.
 * @{
 */
fn mz_compress(pDest: u8*, pDest_len: mz_ulong*, pSource: const(u8)*, source_len: mz_ulong);
fn mz_compress2(pDest: u8*, pDest_len: mz_ulong*, pSource: const(u8)*, source_len: mz_ulong, level: i32);
//! @}

/*!
 * @Returns A (very) conservative upper bound on the amount of data
 * that could be generated by calling `mz_compress`.
 */
fn mz_compressBound(source_len: mz_ulong) mz_ulong;

//! Initialises a decompressor.
fn mz_inflateInit(pStream: mz_streamp) i32;

/*!
 * Like `mz_inflateInit` with an additional option that controls the
 * window size and whether or not the stream has been wrapped with a
 * zlib header/footer.
 * `window_bits` must be `MZ_DEFAULT_WINDOW_BITS` (to parse zlib header/
 * footer) or `-MZ_DEFAULT_WINDOW_BITS` (raw deflate).
 */
fn mz_inflateInit2(pStream: mz_streamp, window_bits: i32) i32;

/*!
 * Decompresses the input stream to the output, consuming only as much
 * of the input as needed, and writing as much to the output as possible.
 *
 * @Params pStream Is the stream to read from and write to. You must initialise/
 * update the `next_in`, `avail_in`, `next_out`, and `avail_out` members.
 * @Params flush May be `MZ_NO_FLUSH`, `MZ_SYNC_FLUSH`, `MZ_FINISH`.
 * On the first call, if `flush` is `MZ_FINISH` it's assumed the input and
 * output buffers are both sized large enough to decompress the entire stream
 * in a single call (this is slightly faster).
 * `MZ_FINISH` implies that there are no more source bytes available beside
 * what's already in the input buffer, and that the output buffer is large
 * enough to hold the rest of the decompressed data.
 * @Returns `MZ_OK` on success. Either more input is needed but not available,
 * and/or there's more output to be written but the output buffer is full.
 * `MZ_STREAM_END` if all needed input has been consumed and all output
 * bytes have been written. For zlib streams, the adler-32 of the decompressed
 * data has also been verified. `MZ_STREAM_ERROR` if the stream is bogus.
 * `MZ_DATA_ERROR` if the deflate stream is invalid. `MZ_PARAM_ERROR` if one
 * of the parameters is invalid. `MZ_BUF_ERROR` if no forward progress is
 * possible because the input buffer is empty but the inflater needs more input
 * to continue, or if the output buffer is not large enough. Call `mz_inflate`
 * again with more input data, or with more room in the output buffer (except
 * when using single call decompression, desribed above).
 */
fn mz_inflate(pStream: mz_streamp, flush: i32) i32;

//! Deinitialises a decompressor.
fn mz_inflateEnd(pStream: mz_streamp) i32;

/*!
 * Single-call decompression.  
 * @Returns `MZ_OK` on success, or one of the error codes from `mz_inflate` on failure.
 */
fn mz_uncompress(pDest: u8*, pDest_len: mz_ulong*, pSource: const(u8)*, source_len: mz_ulong) i32;

/*!
 * @Returns A string description of the specified error code, or `null` if the
 * error code is invalid.
 */
fn mz_error(err: i32) const(char)*;

alias mz_uint8 = u8;
alias mz_int16 = i16;
alias mz_uint16 = u16;
alias mz_uint32 = u32;
alias mz_uint = u32;
alias mz_int64 = i64;
alias mz_uint64 = u64;
alias mz_bool = i32;

enum MZ_FALSE = 0;
enum MZ_TRUE = 1;

enum
{
	MZ_ZIP_MAX_IO_BUF_SIZE = 64*1024,
	MZ_ZIP_MAX_ARCHIVE_FILENAME_SIZE = 512,
	MZ_ZIP_MAX_ARCHIVE_FILE_COMMENT_SIZE = 512
}

struct mz_zip_archive_file_stat
{
	m_file_index: mz_uint32;
	m_central_dir_ofs: mz_uint64;
	m_version_made_by: mz_uint16;
	m_version_needed: mz_uint16;
	m_bit_flag: mz_uint16;
	m_method: mz_uint16;
	m_time: time_t;
	m_crc32: mz_uint32;
	m_comp_size: mz_uint64;
	m_uncomp_size: mz_uint64;
	m_internal_attr: mz_uint16;
	m_external_attr: mz_uint32;
	m_local_header_ofs: mz_uint64;
	m_comment_size: mz_uint32;
	m_is_directory: mz_bool;
	m_is_encrypted: mz_bool;
	m_is_supported: mz_bool;
	m_filename: char[MZ_ZIP_MAX_ARCHIVE_FILENAME_SIZE];
	m_comment: char[MZ_ZIP_MAX_ARCHIVE_FILE_COMMENT_SIZE];
}

alias mz_file_read_func = fn(pOpaque: void*, file_ofs: mz_uint64, pBuf: void*, n: size_t) size_t;
alias mz_file_write_func = fn(pOpaque: void*, file_ofs: mz_uint64, pBuf: const(void)*, n: size_t) size_t;
alias mz_file_needs_keepalive = fn(pOpaque: void*) mz_bool;

struct mz_zip_internal_state {}

alias mz_zip_mode = i32;
enum : mz_zip_mode
{
	MZ_ZIP_MODE_INVALID = 0,
	MZ_ZIP_MODE_READING = 1,
	MZ_ZIP_MODE_WRITING = 2,
	MZ_ZIP_MODE_WRITING_HAS_BEEN_FINALIZED = 3
}

struct mz_zip_archive
{
	m_archive_size: mz_uint64;
	m_central_directory_file_ofs: mz_uint64;
	m_total_files: mz_uint32;
	m_zip_mode: mz_zip_mode;
	m_zip_type: mz_zip_type;
	m_zip_error: mz_zip_error;
	m_file_offset_alignment: mz_uint64;
	m_pAlloc: mz_alloc_func;
	m_pFree: mz_free_func;
	m_pRealloc: mz_realloc_func;
	m_pAlloc_opaque: void*;
	m_pRead: mz_file_read_func;
	m_pWrite: mz_file_write_func;
	m_pNeeds_keepalive: mz_file_needs_keepalive;
	m_pIO_opaque: void*;
	m_PState: mz_zip_internal_state*;
}

struct tinfl_decompressor {}

struct mz_zip_reader_extract_iter_state
{
	pZip: mz_zip_archive*;
	flags: mz_uint;
	status: i32;
	file_crc32: mz_uint;
	read_buf_size, read_buf_ofs, read_buf_avail, comp_remaining,
	out_buf_ofs, cur_file_ofs: mz_uint64;
	file_stat: mz_zip_archive_file_stat;
	pRead_buf: void*;
	pWrite_buf: void*;
	out_blk_remain: size_t;
	inflator: tinfl_decompressor;
}

alias mz_zip_flags = i32;
enum : mz_zip_flags
{
	MZ_ZIP_FLAG_CASE_SENSITIVE = 0x0100,
	MZ_ZIP_FLAG_IGNORE_PATH = 0x0200,
	MZ_ZIP_FLAG_COMPRESSED_DATA = 0x0400,
	MZ_ZIP_FLAG_DO_NOT_SORT_CENTRAL_DIRECTORY = 0x0800,
	MZ_ZIP_FLAG_VALIDATE_LOCATE_FILE_FLAG = 0x1000, /* if enabled, mz_zip_reader_locate_file() will be called on each file as its validated to ensure the func finds the file in the central dir (intended for testing) */
	MZ_ZIP_FLAG_VALIDATE_HEADERS_ONLY = 0x2000,     /* validate the local headers, but don't decompress the entire file and check the crc32 */
	MZ_ZIP_FLAG_WRITE_ZIP64 = 0x4000,               /* always use the zip64 file format, instead of the original zip file format with automatic switch to zip64. Use as flags parameter with mz_zip_writer_init*_v2 */
	MZ_ZIP_FLAG_WRITE_ALLOW_READING = 0x8000,
	MZ_ZIP_FLAG_ASCII_FILENAME = 0x10000
}

alias mz_zip_type = i32;
enum : mz_zip_type
{
	MZ_ZIP_TYPE_INVALID = 0,
	MZ_ZIP_TYPE_USER,
	MZ_ZIP_TYPE_MEMORY,
	MZ_ZIP_TYPE_HEAP,
	MZ_ZIP_TYPE_FILE,
	MZ_ZIP_TYPE_CFILE,
	MZ_ZIP_TOTAL_TYPES
}

alias mz_zip_error = i32;
enum : mz_zip_error
{
	MZ_ZIP_NO_ERROR = 0,
	MZ_ZIP_UNDEFINED_ERROR,
	MZ_ZIP_TOO_MANY_FILES,
	MZ_ZIP_FILE_TOO_LARGE,
	MZ_ZIP_UNSUPPORTED_METHOD,
	MZ_ZIP_UNSUPPORTED_ENCRYPTION,
	MZ_ZIP_UNSUPPORTED_FEATURE,
	MZ_ZIP_FAILED_FINDING_CENTRAL_DIR,
	MZ_ZIP_NOT_AN_ARCHIVE,
	MZ_ZIP_INVALID_HEADER_OR_CORRUPTED,
	MZ_ZIP_UNSUPPORTED_MULTIDISK,
	MZ_ZIP_DECOMPRESSION_FAILED,
	MZ_ZIP_COMPRESSION_FAILED,
	MZ_ZIP_UNEXPECTED_DECOMPRESSED_SIZE,
	MZ_ZIP_CRC_CHECK_FAILED,
	MZ_ZIP_UNSUPPORTED_CDIR_SIZE,
	MZ_ZIP_ALLOC_FAILED,
	MZ_ZIP_FILE_OPEN_FAILED,
	MZ_ZIP_FILE_CREATE_FAILED,
	MZ_ZIP_FILE_WRITE_FAILED,
	MZ_ZIP_FILE_READ_FAILED,
	MZ_ZIP_FILE_CLOSE_FAILED,
	MZ_ZIP_FILE_SEEK_FAILED,
	MZ_ZIP_FILE_STAT_FAILED,
	MZ_ZIP_INVALID_PARAMETER,
	MZ_ZIP_INVALID_FILENAME,
	MZ_ZIP_BUF_TOO_SMALL,
	MZ_ZIP_INTERNAL_ERROR,
	MZ_ZIP_FILE_NOT_FOUND,
	MZ_ZIP_ARCHIVE_TOO_LARGE,
	MZ_ZIP_VALIDATION_FAILED,
	MZ_ZIP_WRITE_CALLBACK_FAILED,
	MZ_ZIP_TOTAL_ERRORS
}

/*!
 * Init a ZIP archive reader.
 * These functions read and validate the archive's central directory.
 * @{
 */
fn mz_zip_reader_init(pZip: mz_zip_archive*, size: mz_uint64, flags: mz_uint32) mz_bool;
fn mz_zip_reader_init_mem(pZip: mz_zip_archive*, pMem: const(void)*, size: size_t, flags: mz_uint32) mz_bool;
fn mz_zip_reader_init_file(pZip: mz_zip_archive*, pFilename: const(char)*, flags: mz_uint32) mz_bool;
fn mz_zip_reader_init_file_v2(pZip: mz_zip_archive*, pFilename: const(char)*, flags: mz_uint, file_start_ofs: mz_uint64, archive_size: mz_uint64) mz_bool;
//! @}

/*! Read an archive from an already opened FILE, beginning at the current
 * file position.
 * The archive is assumed to be archive_size bytes long. If archive_size
 * is < 0, then the entire rest of the file is assumed to contain the archive.
 * The FILE will NOT be closed when mz_zip_reader_end() is called.
 */
fn mz_zip_reader_init_cfile(pZip: mz_zip_archive*, pFile: MZ_FILE*, archive_size: mz_uint64, flags: mz_uint) mz_bool;

//! Get the total number of files in the archive.
fn mz_zip_reader_get_num_files(pZip: mz_zip_archive*) mz_uint;

//! Get detailed information about an archive file entry.
fn mz_zip_reader_file_stat(pZip: mz_zip_archive*, file_index: mz_uint, pStat: mz_zip_archive_file_stat*) mz_bool;

/*! MZ_TRUE if the file is in zip64 format.
 * A file is considered zip64 if it contained a zip64 end of central directory marker, or if it contained any zip64 extended file information fields in the central directory. */
fn mz_zip_is_zip64(pZip: mz_zip_archive*) mz_bool;

/* Returns the total central directory size in bytes. */
/* The current max supported size is <= MZ_UINT32_MAX. */
fn mz_zip_get_central_dir_size(pZip: mz_zip_archive*) size_t;

//! Is an archive file entry a directory entry?
fn mz_zip_reader_is_file_a_directory(pZip: mz_zip_archive*, file_index: mz_uint) mz_bool;
/*! MZ_TRUE if the file is encrypted/strong encrypted. */
fn mz_zip_reader_is_file_encrypted(pZip: mz_zip_archive*, file_index: mz_uint) mz_bool;
/*! MZ_TRUE if the compression method is supported, and the file is not encrypted, and the file is not a compressed patch file. */
fn mz_zip_reader_is_file_supported(pZip: mz_zip_archive*, file_index: mz_uint) mz_bool;

/*!
 * Retrieves the filename of an archive file entry.
 * @Returns The number of bytes written to `pFilename`, or if `filename_buf_size`
 * is 0 this function returns the number of bytes needed to fully store the filename.
 */
fn mz_zip_reader_get_filename(pZip: mz_zip_archive*, file_index: mz_uint, pFilename: char*, filename_buf_size: mz_uint) mz_uint;

/*!
 * Locate a file in the archive's central directory.  
 * Valid flags: `MZ_ZIP_FLAG_CASE_SENSITIVE`, `MZ_ZIP_FLAG_IGNORE_PATH`.
 * @Returns -1 if the file cannot be found.
 */
fn mz_zip_reader_locate_file(pZip: mz_zip_archive*, pName: const(char)*, pComment: const(char)*, flags: mz_uint) i32;
/*! Returns MZ_FALSE if the file cannot be found. */
fn mz_zip_locate_file_v2(pZip: mz_zip_archive*, pName: const(char)*, pComment: const(char)*, flags: mz_uint, pIndex: mz_uint32*) mz_bool;

fn mz_zip_set_last_error(pZip: mz_zip_archive*, err_num: mz_zip_error) mz_zip_error;
fn mz_zip_peek_last_error(pZip: mz_zip_archive*) mz_zip_error;
fn mz_zip_clear_last_error(pZip: mz_zip_archive*) mz_zip_error;
fn mz_zip_get_last_error(pZip: mz_zip_archive*) mz_zip_error;
fn mz_zip_get_error_string(mz_err: mz_zip_error) const(char)*;


/*!
 * Extracts an archive file to a memory buffer using no memory allocation.
 * @{
 */
fn mz_zip_reader_extract_to_mem_no_alloc(pZip: mz_zip_archive*, file_index: mz_uint, pBuf: void*, buf_size: size_t, flags: mz_uint, pUser_read_buf: void*, user_read_buf_size: size_t) mz_bool;
fn mz_zip_reader_extract_file_to_mem_no_alloc(pZip: mz_zip_archive*, pFilename: const(char)*, pBuf: void*, buf_size: size_t, flags: mz_uint, pUser_read_buf: void*, user_read_buf_size: size_t) mz_bool;
//! @}

/*!
 * Extracts an archive file to a memory buffer.
 * @{
 */
fn mz_zip_reader_extract_to_mem(pZip: mz_zip_archive*, file_index: mz_uint, pBuf: void*, buf_size: size_t, flags: mz_uint) mz_bool;
fn mz_zip_reader_extract_file_to_mem(pZip: mz_zip_archive*, pFilename: const(char)*, pBUf: void*, buf_size: size_t, flags: mz_uint) mz_bool;
//! @}

/*!
 * Extracts an archive file to a dynamically allocated heap buffer.
 * @{
 */
fn mz_zip_reader_extract_to_heap(pZip: mz_zip_archive, file_index: mz_uint, pSize: size_t*, flags: mz_uint) void*;
fn mz_zip_reader_extract_file_to_heap(pZip: mz_zip_archive, pFilename: const(char)*, pSize: size_t*, flags: mz_uint) void*;
//! @}

/*!
 * Extract an archive file using a callback function to output the file's data.
 * @{
 */
fn mz_zip_reader_extract_to_callback(pZip: mz_zip_archive*, file_index: mz_uint, pCallback: mz_file_write_func, pOpaque: void*, flags: mz_uint) mz_bool;
fn mz_zip_reader_extract_file_to_callback(pZip: mz_zip_archive*, pFilename: const(char)*, pCallback: mz_file_write_func, pOpaque: void*, flags: mz_uint) mz_bool;
//! @}

/*!
 * Extracts an archive to disk and sets its last accessed and modified times.  
 * This function only extracts files, not archive directory records.
 * @{
 */
fn mz_zip_reader_extract_to_file(pZip: mz_zip_archive*, file_index: mz_uint, pDst_filename: const(char)*, flags: mz_uint) mz_bool;
fn mz_zip_reader_extract_file_to_file(pZip: mz_zip_archive*, pArchive_filename: const(char)*, pDst_filename: const(char)*, flags: mz_uint) mz_bool;
//! @}

/*!
 * Ends archive reading, freeing all allocations, and closing the input archive
 * file if mz_zip_reader_init_file() was used.
 */
fn mz_zip_reader_end(pZip: mz_zip_archive*) mz_bool;

/*! Clears a mz_zip_archive struct to all zeros.
 * Important: This must be done before passing the struct
 * to any mz_zip functions.
 */
fn mz_zip_zero_struct(pZip: mz_zip_archive*);

fn mz_zip_get_mode(pZip: mz_zip_archive*) mz_zip_mode;
fn mz_zip_get_type(pZip: mz_zip_archive*) mz_zip_type;

fn mz_zip_get_archive_size(pZip: mz_zip_archive*) mz_uint64;
fn mz_zip_get_archive_file_start_offset(pZip: mz_zip_archive*) mz_uint64;
fn mz_zip_get_cfile(pZip: mz_zip_archive*) MZ_FILE*;

/* Reads n bytes of raw archive data, starting at file offset file_ofs, to pBuf. */
fn mz_zip_read_archive_data(pZip: mz_zip_archive*, file_ofs: mz_uint64, pBuf: void*, n: size_t) size_t;

/*!
 * Inits a ZIP archive writer.
 * @{
 */
fn mz_zip_writer_init(pZip: mz_zip_archive*, existing_size: mz_uint64) mz_bool;
fn mz_zip_writer_init_heap(pZip: mz_zip_archive*, size_to_reserve_at_beginning: size_t, initial_allocation_size: size_t) mz_bool;
fn mz_zip_writer_init_file(pZip: mz_zip_archive*, pFilename: const(char)*, size_to_reserve_at_beginning: mz_uint64) mz_bool;
//! @}

/*! 
 * Converts a ZIP archive reader object into a writer object, to allow efficient
 * in-place file appends to occur on an existing archive.
 *
 * For archives opened using `mz_zip_reader_init_file`, `pFilename` must be the
 * archive's filename so it can be reopened for writing. If the file can't be
 * reopened, `mz_zip_reader_end` will be called.
 *
 * For archives opened using `mz_zip_reader_init_mem`, the memory block must be
 * growable using the `realloc` callback (which defaults to realloc unless
 * you've overridden it).
 *
 * Finally, for archives opened using `mz_zip_reader_init`, the `mz_zip_archive`'s
 * user provided `m_pWrite` function cannot be `null`.
 *
 * Note: In-place archive modification is not recommended unless you know what
 * you're doing, because if execution stops or something goes wrong before
 * the archive is finalized the file's central directory will be hosed.
 */
fn mz_zip_writer_init_from_reader(pZip: mz_zip_archive*, pFilename: const(char)*) mz_bool;

/*!
 * Adds the contents of a memory buffer to an archive. These functions record the
 * current local time into the archive.
 *
 * To add a directory entry, call this method with an archive name ending in a
 * forwardslash with empty buffer.
 *
 * level_and_flags - compression level (0-10, see `MZ_BEST_SPEED`,
 * `MZ_BEST_COMPRESSION`, etc.) logically OR'd with zero or more `mz_zip_flags`,
 * or just set to `MZ_DEFAULT_COMPRESSION`.
 *
 * @{
 */
fn mz_zip_writer_add_mem(pZip: mz_zip_archive*, pArchive_name: const(char)*, pBuf: const(void)*, buf_size: size_t, level_and_flags: mz_uint) mz_bool;
fn mz_zip_writer_add_mem_ex(pZip: mz_zip_archive*, pArchive_name: const(char)*, pBuf: const(void)*, buf_size: size_t, pComment: const(void)*, comment_size: mz_uint16, level_and_flags: mz_uint, uncomp_size: mz_uint64, uncomp_crc32: mz_uint32) mz_bool;
//! @}

/*! 
 * Adds the contents of a disk file to an archive.  
 * This function also records the disk file's modified time into the archive.
 * level_and_flags - compression level (0-10, see `MZ_BEST_SPEED`,
 * `MZ_BEST_COMPRESSION`, etc.) logically OR'd with zero or more `mz_zip_flags`,
 * or just set to `MZ_DEFAULT_COMPRESSION`.
 */
fn mz_zip_writer_add_file(pZip: mz_zip_archive*, pArchive_name: const(char)*, pSrc_filename: const(char)*, pComment: const(void)*, comment_size: mz_uint16, level_and_flags: mz_uint) mz_bool;

/*!
 * Adds a file to an archive by fully cloning the data from another archive.
 * This function fully clones the source file's compressed data (no recompression),
 * along with its full filename, extra data, and comment fields.
 */
fn mz_zip_writer_add_from_zip_reader(pZip: mz_zip_archive*, pSource_zip: mz_zip_archive*, file_index: mz_uint) mz_bool;

/*!
 * Finalizes the archive by writing the central directory records followed by the end
 * of central directory record.
 * After an archive is finalized, the only valid call on the `mz_zip_archive`
 * struct is `mz_zip_writer_end`.
 * An archive must be manually finalized by calling this function for it to be valid.
 */
fn mz_zip_writer_finalize_archive(pZip: mz_zip_archive*) mz_bool;
fn mz_zip_writer_finalize_heap_archive(pZip: mz_zip_archive*, pBuf: void**, pSize: size_t*) mz_bool;

/*!
 * Ends archive writing, freeing all allocations, and closing the output file
 * if `mz_zip_writer_init_file` was used.
 * Note for the archive to be valid, it must have been finalized before ending.
 */
fn mz_zip_writer_end(pZip: mz_zip_archive*) mz_bool;

/*!
 * `mz_zip_add_mem_to_archive_file_in_place` efficiently (but not atomically)
 * appends a memory blob to a ZIP archive.
 * level_and_flags - compression level (0-10, see MZ_BEST_SPEED, MZ_BEST_COMPRESSION,
 * etc.) logically OR'd with zero or more mz_zip_flags, or just set to
 * MZ_DEFAULT_COMPRESSION.
 */
fn mz_zip_add_mem_to_archive_file_in_place(pZip_filename: const(char)*, pArchive_name: const(char)*, pBuf: const(void)*, buf_size: size_t, pComment: const(void)*, comment_size: mz_uint16, level_and_flags: mz_uint) mz_bool;

/*!
 * Reads a single file from an archive into a heap block.
 * Returns `null` on failure.
 */
fn mz_zip_extract_archive_file_to_heap(pZip_filename: const(char)*, pArchive_name: const(char)*, pSize: size_t*, zip_flags: mz_uint) void*;
