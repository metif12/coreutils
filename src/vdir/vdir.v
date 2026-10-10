import common.vdir as vdirmod
import os

fn main() {
	set := vdirmod.parse_args(os.args[1..])
	output, code := vdirmod.run(set)
	if output != '' {
		println(output)
	}
	exit(code)
}
