// Nix-only tests: `who` reads the utmp database, which Windows does not have,
// so there is nothing to compare against there. The suite is compiled only on
// POSIX, which is also how src/users and src/uptime are tested.
//
// These cover the parts that do not need a live utmp file: option parsing and
// row rendering. The differential against GNU 9.4's real output was done
// separately, since that needs actual login records.
import os

fn test_parse_args_defaults() {
	s := args()
	assert !s.count
	assert !s.heading
	assert !s.boot
}

fn test_parse_args_a_bare_operand_is_a_file() {
	// Flag-free operands are files to read, so they must not be mistaken for
	// options.
	s := parse_for_test(['somefile'])
	assert s.files == ['somefile']
	assert !s.boot
}

fn test_parse_args_am_i_is_two_operands() {
	// "who am i" is two operands, and that is the normal spelling.
	s := parse_for_test(['am', 'i'])
	assert s.my_name
}

fn test_parse_args_boot_and_count() {
	b := parse_for_test(['-b'])
	assert b.boot
	assert !b.count

	q := parse_for_test(['-q'])
	assert q.count
	assert !q.boot
}

fn test_parse_args_heading_and_short() {
	h := parse_for_test(['-H'])
	assert h.heading
	assert !h.short

	s := parse_for_test(['-s'])
	assert s.short
	assert !s.heading
}

fn test_time_column_format() {
	// GNU's layout is YYYY-MM-DD HH:MM, zero-padded, in UTC.
	assert format_time(1700000000) == '2023-11-14 22:13'
}

fn test_boot_record_uses_the_same_column_widths() {
	// The boot record is rendered with an empty name and the line spelled
	// "system boot", so it lands at the same column offsets as a user row
	// rather than at a hand-picked indentation.
	entries := [Entry{
		name: ''
		line: 'system boot'
		time: 1700000000
		kind: 2
	}]
	rows := show_rows_for_test(entries, Settings{
		boot: true
	})
	assert rows.len == 1
	assert rows[0] == '          system boot 2023-11-14 22:13'
}

fn test_default_filters_out_boot_records() {
	// A boot record has no user name, so the default listing must not show it.
	entries := [Entry{
		name: ''
		line: 'system boot'
		time: 1700000000
		kind: 2
	}, Entry{
		name: 'root'
		line: 'pts/0'
		time: 1700000000
		kind: 7
	}]
	rows := show_rows_for_test(entries, Settings{})
	assert rows.len == 1
	assert rows[0].starts_with('root')
}

fn test_count_row() {
	entries := [Entry{
		name: 'root'
		line: 'pts/0'
	}, Entry{
		name: 'mr'
		line: 'pts/1'
	}]
	assert count_row_for_test(entries) == 'root mr\n# users=2'
}
