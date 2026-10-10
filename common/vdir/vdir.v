module vdir

import common
import os
import time

pub struct Settings {
pub mut:
	all       bool
	recursive bool
	reverse   bool
	by_time   bool
	by_size   bool
	operands  []string
}

// Entry is one row of the long listing.
struct Entry {
mut:
	mode  string
	links int
	owner string
	group string
	size  u64
	mtime i64
	name  string
	path  string
}

// run renders the long listing and returns it with the exit status.
pub fn run(set Settings) (string, int) {
	mut out := []string{}
	mut targets := set.operands.clone()
	if targets.len == 0 {
		targets = ['.']
	}
	mut failed := false

	for target in targets {
		st := os.lstat(target) or {
			eprintln('vdir: cannot access ${quoted(target)}: No such file or directory')
			failed = true
			continue
		}
		if st.get_filetype() == .directory {
			list_directory(mut out, target, set, true)
		} else {
			out << render([stat_entry(target, os.base(target))], u64(0))
		}
	}
	if failed {
		return out.join('\n'), 2
	}
	return out.join('\n'), 0
}

fn quoted(s string) string {
	return "'${s}'"
}

fn list_directory(mut out []string, path string, set Settings, is_root bool) {
	entries := os.ls(path) or {
		return
	}
	mut names := []string{}
	if set.all {
		// os.ls omits the two self-referential entries, as in dir.
		names << '.'
		names << '..'
	}
	for e in entries {
		names << e
	}
	names = sorted_names(names, path, set)

	if set.recursive && !is_root {
		out << ''
	}
	if set.recursive {
		out << '${path}:'
	}

	mut rows := []Entry{}
	mut blocks := u64(0)
	for name in names {
		child := os.join_path(path, name)
		rows << stat_entry(child, name)
		blocks += block_count(child)
	}
	out << render(rows, blocks)

	if !set.recursive {
		return
	}
	for name in names {
		if name == '.' || name == '..' {
			continue
		}
		child := os.join_path(path, name)
		st := os.lstat(child) or { continue }
		if st.get_filetype() == .directory {
			list_directory(mut out, child, set, false)
		}
	}
}

// sorted_names applies the requested order, exactly as dir does. The entry names
// are joined onto the directory before -t or -S compares them, because those
// keys live in the file system and a bare name says nothing about size or time.
fn sorted_names(names []string, path string, set Settings) []string {
	mut rows := []SortName{}
	for n in names {
		rows << SortName{
			name: n
			path: os.join_path(path, n)
		}
	}

	if set.by_time {
		rows.sort_with_compare(fn (a &SortName, b &SortName) int {
			ma := mtime_of(a.path)
			mb := mtime_of(b.path)
			if ma > mb {
				return -1
			}
			if ma < mb {
				return 1
			}
			return cmp_names(a, b)
		})
	} else if set.by_size {
		rows.sort_with_compare(fn (a &SortName, b &SortName) int {
			sa := size_of(a.path)
			sb := size_of(b.path)
			if sb > sa {
				return -1
			}
			if sb < sa {
				return 1
			}
			return cmp_names(a, b)
		})
	} else {
		rows.sort_with_compare(fn (a &SortName, b &SortName) int {
			return cmp_names(a, b)
		})
	}

	if set.reverse {
		rows.reverse_in_place()
	}
	mut out := []string{cap: rows.len}
	for r in rows {
		out << r.name
	}
	return out
}

struct SortName {
	name string
	path string
}

fn cmp_names(a &SortName, b &SortName) int {
	if a.name < b.name {
		return -1
	}
	if a.name > b.name {
		return 1
	}
	return 0
}

fn mtime_of(path string) i64 {
	st := os.lstat(path) or { return 0 }
	return st.mtime
}

fn size_of(path string) u64 {
	st := os.lstat(path) or { return 0 }
	return st.size
}

// stat_entry builds the long-format row for one name.
fn stat_entry(path string, name string) Entry {
	mut e := Entry{
		name: name
		path: path
	}
	st := os.lstat(path) or { return e }
	e.mode = mode_string(st)
	e.links = int(st.nlink)
	e.owner = owner_name(st.uid)
	e.group = group_name(st.gid)
	e.size = st.size
	e.mtime = st.mtime
	return e
}

// block_count rounds a size up to a whole 1K block, which is what the total
// line sums.
fn block_count(path string) u64 {
	st := os.lstat(path) or { return 0 }
	return (st.size + 1023) / 1024
}

// mode_string renders the ten-character rwx form. The leading character is the
// file type, which os.Stat carries in the high bits.
fn mode_string(st os.Stat) string {
	mut bits := st.mode & 0o7777
	mut chars := []u8{len: 9, init: `-`}
	// Bits are taken three at a time from the top: rwx for user, group, other.
	for triple in 0 .. 3 {
		mut b := bits
		// Shift so this triple's read bit lands in bit 8.
		for i := 0; i < triple; i++ {
			b = b >> 3
		}
		if b & 0o4 != 0 {
			chars[triple * 3] = `r`
		}
		if b & 0o2 != 0 {
			chars[triple * 3 + 1] = `w`
		}
		if b & 0o1 != 0 {
			chars[triple * 3 + 2] = `x`
		}
	}
	type_char := match st.get_filetype() {
		.directory { u8(`d`) }
		else { u8(`-`) }
	}
	mut out := []u8{cap: 10}
	out << type_char
	out << chars
	return out.bytestr()
}

// owner_name and group_name are placeholders: V's os.Stat carries numeric ids
// and this port has no account lookup yet, so the numeric id is shown rather
// than a name. GNU shows the name, and that is a documented gap.
fn owner_name(uid u32) string {
	return uid.str()
}

fn group_name(gid u32) string {
	return gid.str()
}

// render lays out the rows with column widths computed from the data. GNU
// right-justifies the link count and size to the widest value present, which is
// why a directory of small files still shows a wide size column.
fn render(rows []Entry, blocks u64) string {
	mut links_w := 1
	mut size_w := 1
	for r in rows {
		links_w = imax(links_w, r.links.str().len)
		size_w = imax(size_w, r.size.str().len)
	}

	mut text := 'total ${blocks}'
	for r in rows {
		row := '${r.mode} ${pad(r.links.str(), links_w)} ${r.owner} ${r.group} ${pad(r.size.str(), size_w)} ${date_column(r.mtime)} ${r.name}'
		text += '\n' + row
	}
	return text
}

// date_column renders the mtime the way ls does: "Mon DD HH:MM" for a file
// modified in the last six months, and "Mon DD  YYYY" for anything older.
fn date_column(epoch i64) string {
	t := time.unix(epoch)
	months := ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec']
	mut name := 'Jan'
	if t.month >= 1 && t.month <= 12 {
		name = months[t.month - 1]
	}
	day := pad(int(t.day).str(), 2)
	if t.year == time.now().year {
		return '${name} ${day} ${pad0(int(t.hour))}:${pad0(int(t.minute))}'
	}
	return '${name} ${day}  ${t.year}'
}

fn pad0(n int) string {
	if n < 10 {
		return '0${n}'
	}
	return n.str()
}

fn pad(s string, w int) string {
	if s.len >= w {
		return s
	}
	return ' '.repeat(w - s.len) + s
}

fn imax(a int, b int) int {
	if a > b {
		return a
	}
	return b
}

pub fn parse_args(args []string) Settings {
	mut s := Settings{}
	mut operands := []string{}

	for i := 0; i < args.len; i++ {
		a := args[i]
		if a == '--' {
			operands << args[i + 1..]
			break
		}
		if a == '--help' {
			print_help()
			exit(0)
		}
		if a == '--version' {
			println('vdir (V coreutils) ${common.version}')
			exit(0)
		}
		if !a.starts_with('-') || a == '-' {
			operands << a
			continue
		}
		if a.starts_with('--') {
			match a {
				'--all' { s.all = true }
				'--recursive' { s.recursive = true }
				'--reverse' { s.reverse = true }
				'--color', '--color=always', '--color=auto' {}
				else {
					common.exit_with_error_message('vdir', "unrecognized option '${a}'")
				}
			}
			continue
		}

		for c in a[1..] {
			match c {
				`a` { s.all = true }
				`R` { s.recursive = true }
				`r` { s.reverse = true }
				`l`, `C`, `1` {}
				`t` { s.by_time = true }
				`S` { s.by_size = true }
				else {
					common.exit_with_error_message('vdir', "invalid option -- '${c.ascii_str()}'")
				}
			}
		}
	}

	s.operands = operands
	return s
}

fn print_help() {
	println('Usage: vdir [OPTION]... [FILE]...')
	println('List information about the FILEs (the current directory by default).')
	println('')
	println('  -a, --all            do not ignore entries starting with .')
	println('  -R, --recursive      list subdirectories recursively')
	println('  -r, --reverse        reverse order while sorting')
	println('      --help        display this help and exit')
	println('      --version     output version information and exit')
}
