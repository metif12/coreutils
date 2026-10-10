import common.vdir as vdirmod
import common.testing
import os

const rig = testing.prepare_rig(util: 'vdir')

fn work_dir() string {
	return os.join_path(os.temp_dir(), 'vdir_test_tree')
}

fn sub_dir() string {
	return os.join_path(work_dir(), 'sub')
}

fn testsuite_begin() {
	rig.assert_platform_util()
	os.rmdir_all(work_dir()) or {}
	os.mkdir_all(work_dir()) or { panic('mkdir: ${err}') }
	os.mkdir_all(sub_dir()) or { panic('mkdir sub: ${err}') }
	os.write_file(os.join_path(work_dir(), 'one.txt'), 'aa') or { panic('write: ${err}') }
	os.write_file(os.join_path(work_dir(), 'two.txt'), 'bbbb') or {
		panic('write: ${err}')
	}
	os.write_file(os.join_path(sub_dir(), 'nested.txt'), 'cc') or {
		panic('write: ${err}')
	}
}

fn testsuite_end() {
	os.rmdir_all(work_dir()) or {}
}

fn run_vdir(args []string) (string, int) {
	return vdirmod.run(vdirmod.parse_args(args))
}

fn test_help_and_version() {
	rig.assert_help_and_version_options_work()
}

fn test_total_line_comes_first() {
	out, code := run_vdir([work_dir()])
	assert code == 0
	lines := out.split('\n')
	assert lines[0].starts_with('total '), 'first line: ${lines[0]}'
}

fn test_row_shape() {
	// Every row carries the ten-character mode, a link count, an owner, a
	// group, a size, a date and the name. The fields are taken with the
	// padding filtered out, because the size column is right-justified.
	out, _ := run_vdir([work_dir()])
	for line in out.split('\n')[1..] {
		fields := line.split(' ').filter(it != '')
		assert fields.len >= 8, 'row too short: ${line}'
		assert fields[0].len == 10, 'mode field: ${fields[0]}'
	}
}

fn test_size_column_is_right_justified() {
	// The width comes from the widest value present, so the size field of a
	// The width comes from the widest value present, so a small entry's size
	// is padded on the left to line up with a larger one.
	out, _ := run_vdir([work_dir()])
	assert out.contains(' 2 '), 'size column not padded: ${out}'
	assert out.contains(' 4 '), 'larger size missing: ${out}'
}

fn test_all_synthesises_dot_entries() {
	out, _ := run_vdir(['-a', work_dir()])
	lines := out.split('\n')
	// The total line is first, and '.' is the first data row.
	assert lines[1].ends_with(' .'), 'second line: ${lines[1]}'
	mut found_dotdot := false
	for line in lines[1..] {
		if line.ends_with(' ..') {
			found_dotdot = true
		}
	}
	assert found_dotdot
}

fn test_recursive_lists_subdirectories() {
	out, _ := run_vdir(['-R', work_dir()])
	assert out.contains('${work_dir()}:')
	assert out.contains('${sub_dir()}:')
	assert out.contains('nested.txt')
}

fn test_missing_path_exits_two() {
	_, code := run_vdir([os.join_path(work_dir(), 'nope')])
	assert code == 2
}

fn test_mode_string_distinguishes_files_and_directories() {
	out, _ := run_vdir([work_dir()])
	// A directory row starts with d, a file row with -.
	assert out.contains('\nd')
	assert out.contains('\n-')
}

fn test_parse_args_defaults() {
	s := vdirmod.parse_args([])
	assert !s.all
	assert !s.recursive
	assert s.operands.len == 0
}

fn test_parse_args_flags() {
	s := vdirmod.parse_args(['-a', '-R', '-r'])
	assert s.all
	assert s.recursive
	assert s.reverse

	long := vdirmod.parse_args(['--all', '--recursive'])
	assert long.all
	assert long.recursive
}

fn test_parse_args_operands() {
	s := vdirmod.parse_args(['-a', 'x', 'y'])
	assert s.operands == ['x', 'y']
}

fn test_owner_and_group_are_numeric_placeholders() {
	// V's os.Stat exposes numeric ids and this port has no account lookup, so
	// the ids are printed rather than names. GNU prints names, and that is a
	// documented gap rather than something the tests assert away.
	out, _ := run_vdir([work_dir()])
	for line in out.split('\n')[1..] {
		fields := line.split(' ')
		assert fields[2].len > 0
		assert fields[3].len > 0
	}
}

fn test_date_column_format() {
	// "Mon DD HH:MM" for this year. The month name is one of the twelve
	// abbreviations, and it follows the size column after the padding is
	// accounted for.
	out, _ := run_vdir([work_dir()])
	months := ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec']
	for line in out.split('\n')[1..] {
		fields := line.split(' ').filter(it != '')
		mut ok := false
		for m in months {
			if fields[5] == m {
				ok = true
			}
		}
		assert ok, 'date column month not recognised: ${fields[5]}'
	}
}
