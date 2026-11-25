module main

import os
import trashcli

fn main() {
	exit(trashcli.run(os.args[1..]))
}
