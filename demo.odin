package md4c

/*

import "core:strings"
import "core:fmt"
import "core:os"
import "core:io"

SRC :: #load("example.md", string)

main :: proc(){
	writer_example: {
		file, _ := os.open("output.html", os.O_CREATE | os.O_RDWR, 0o600)
		defer os.close(file)
		stream := os.stream_from_handle(file)

		fmt.println("Writer Status:", to_html(SRC, stream, Parser_Flags_GitHub))
	}

	builder_example: {
		sb : strings.Builder
		strings.builder_init_len_cap(&sb, 0, len(SRC))

		fmt.println("Builder:", to_html(SRC, &sb, Parser_Flags_GitHub))
		fmt.println(string(sb.buf[:]))
	}

	string_example: {
		s, err := to_html(SRC, Parser_Flags_GitHub)
		fmt.println("String:", err)
		fmt.println(s)
	}
}

*/
