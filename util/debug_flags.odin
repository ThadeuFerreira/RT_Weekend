package util

// VERBOSE_DEBUG is a convenience build flag that enables broad diagnostics.
// Use: -define:VERBOSE_DEBUG=1
//
// This flag is consumed by package-specific defaults (e.g. allocator tracking,
// UI event logging, idle GPU tracing). Individual flags can still be overridden
// explicitly via their own -define values.
VERBOSE_DEBUG :: #config(VERBOSE_DEBUG, 0)
VERBOSE_DEBUG_ENABLED :: VERBOSE_DEBUG != 0
