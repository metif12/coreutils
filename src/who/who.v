import common
import os
import time

const app_name = 'who'

pub struct Settings {
mut:
	files      []string
	all        bool // -a
	boot       bool // -b
	count      bool // -q
	dead       bool // -d
	heading    bool // -H
	login      bool // -l
	lookup     bool // --lookup
	mesg       bool // -T
	process_id bool // -u
	run_level  bool // -r
	short      bool // -s
	my_name    bool // 'am i'
}

// Entry is one utmp record, normalised for display.
struct Entry {
mut:
	name    string
	line    string
	time    i64
	comment string
	pid     int
	kind    int // C.ut_type, so -b and -r can filter on it
}

fn main() {
	settings := args()
	entries := utmp_entries(settings.files, settings)
	if entries.len == 0 {
		exit(0)
	}
	if settings.count {
		show_count(entries)
	} else {
		show_entries(entries, settings)
	}
}

// utmp_entries reads the default utmp file, or any named ones. `who` with no
// operand reads /var/run/utmp, which is what the shared reader defaults to.
//
// The default listing shows user processes only. The boot and runlevel records
// GNU prints under -b and -r carry no user name, so filtering on
// USER_PROCESS is what keeps them out of the default table.
fn utmp_entries(files []string, settings Settings) []Entry {
	names := if files.len == 0 { [''] } else { files }
	mut entries := []Entry{}
	for name in names {
		cname := if name == '' { common.utmp_file_charptr } else { name.str }
		mut utmp_buf := []C.utmpx{}
		unsafe {
			mode := if settings.boot || settings.run_level {
				common.ReadUtmpOptions.undefined
			} else {
				common.ReadUtmpOptions.user_process
			}
			common.read_utmp(cname, mut utmp_buf, mode)
			for u in utmp_buf {
				user := cstring_to_vstring(&u.ut_user[0])
				line := cstring_to_vstring(&u.ut_line[0])
				if user == '' && line == '' {
					continue
				}
				entries << Entry{
					name:    user
					line:    line
					time:    i64(u.ut_tv.tv_sec)
					comment: cstring_to_vstring(&u.ut_host[0])
					pid:     u.ut_pid
					kind:    u.ut_type
				}
			}
		}
	}
	return entries
}

fn show_count(entries []Entry) {
	println(count_row_for_test(entries))
}

// count_row_for_test builds the -q output: the names, then the count line.
fn count_row_for_test(entries []Entry) string {
	names := entries.map(it.name)
	return '${names.join(' ')}\n# users=${names.len}'
}

fn show_entries(entries []Entry, settings Settings) {
	println(show_rows_for_test(entries, settings).join('\n'))
}

// show_rows_for_test builds the table rows. It is separate from printing so the
// layout can be asserted on without spawning the binary.
fn show_rows_for_test(entries []Entry, settings Settings) []string {
	mut rows := []string{}
	if settings.heading {
		rows << 'NAME     LINE         TIME             COMMENT'
	}
	shown := visible_entries(entries, settings)
	for e in shown {
		mut row := '${e.name:-8s} ${e.line:-12s} ${format_time(e.time)}'
		if settings.process_id {
			row += ' ${idle(e.line)} ${pad(e.pid.str(), 6)}'
		}
		rows << row
	}
	return rows
}

// visible_entries applies the -b / -r filters and normalises the boot record.
// The default listing shows user processes only; -b shows the boot record,
// which is not a user process, and GNU spells it with an empty name and the
// line "system boot" rather than the raw "~".
const boot_time = 2
const run_level = 1

fn visible_entries(entries []Entry, settings Settings) []Entry {
	if settings.run_level && !settings.all {
		mut out := []Entry{}
		for e in entries {
			if e.kind == run_level {
				out << e
			}
		}
		return out
	}
	if settings.boot && !settings.all {
		mut out := []Entry{}
		for e in entries {
			if e.kind == boot_time {
				mut b := e
				b.name = ''
				b.line = 'system boot'
				out << b
			}
		}
		return out
	}
	return entries
}

// parse_for_test wraps args() so the tests can drive option parsing without
// reading os.args.
pub fn parse_for_test(items []string) Settings {
	saved := os.args
	os.args = ['who']
	os.args << items
	s := args()
	os.args = saved
	return s
}

// format_time is GNU's "YYYY-MM-DD HH:MM" column.
fn format_time(t i64) string {
	d := time.unix(t)
	return '${d.year:04d}-${pad(int(d.month).str(), 2)}-${pad(int(d.day).str(), 2)} ${pad(int(d.hour).str(), 2)}:${pad(int(d.minute).str(), 2)}'
}

// idle prints the time since the terminal was last used, which GNU takes from
// the device's access time. A line that cannot be stat'd prints as '.'.
fn idle(line string) string {
	if line == '' || !line.starts_with('pts/') && !line.starts_with('tty') {
		return '.'
	}
	dev := '/dev/${line}'
	st := os.lstat(dev) or { return '.' }
	now := time.now().unix()
	idle := if now > st.atime { now - st.atime } else { i64(0) }
	return idle.str()
}

fn pad(s string, w int) string {
	if s.len >= w {
		return s
	}
	return ' '.repeat(w - s.len) + s
}

// args is public so the option parsing can be tested without spawning a
// binary, which matters because the suite is nix-only.
pub fn args() Settings {
	mut fp := common.flag_parser(os.args)
	fp.application(app_name)
	fp.description('Show who is logged on.')
	fp.allow_unknown_args()

	delete := fp.bool('all', `a`, false, 'same as -b -d --login -p -r -t -T -u')
	boot := fp.bool('boot', `b`, false, 'time of last system boot')
	count := fp.bool('count', `q`, false, 'all login names and number of users logged on')
	dead := fp.bool('dead', `d`, false, 'print dead processes')
	heading := fp.bool('heading', `H`, false, 'print line of column headings')
	login := fp.bool('login', `l`, false, 'print system login processes')
	lookup := fp.bool('lookup', 0, false, 'attempt to canonicalize hostnames via DNS')
	mesg := fp.bool('mesg', `T`, false, "add user's message status as +, - or ?")
	process_id := fp.bool('users', `u`, false, 'list users logged in')
	run_level := fp.bool('runlevel', `r`, false, 'print current runlevel')
	short := fp.bool('short', `s`, false, 'print only name, line, and time (default)')

	mut st := Settings{
		all:        delete
		boot:       boot
		count:      count
		dead:       dead
		heading:    heading
		login:      login
		lookup:     lookup
		mesg:       mesg
		process_id: process_id
		run_level:  run_level
		short:      short
	}

	rest := fp.remaining_parameters()
	if rest.len >= 2 && rest[0] == 'am' && (rest[1] == 'i' || rest[1] == 'I') {
		// "who am i" is two operands, and that is the normal spelling.
		st.my_name = true
		return st
	}
	st.files = rest
	return st
}
