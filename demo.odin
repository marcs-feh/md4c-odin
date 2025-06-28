package md4c

import "core:fmt"

SRC :: #load("example.md", string)

main :: proc(){
	fmt.println(to_html_string(SRC, DIALECT_GITHUB))
}

