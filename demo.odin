package md4c

import "core:fmt"
import "core:os"
import "core:io"

SRC :: #load("example.md", string)

main :: proc(){
	writer_example: {
		file, _ := os.open("output.html", os.O_CREATE | os.O_RDWR, 0o600)
		defer os.close(file)
		stream := os.stream_from_handle(file)

		fmt.println(to_html(SRC, stream, Parser_Flags_GitHub))
	}

	builder_example: {
	}
}
