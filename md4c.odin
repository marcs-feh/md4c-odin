package md4c

import "base:runtime"
import "core:c"
import "core:fmt"
import "core:strings"
import "core:io"

foreign import md4c "md4c.o"

Parser_Flag :: enum c.int {
	Collapse_Whitespace        = 1,  /* In MD_TEXT_NORMAL, collapse non-trivial whitespace into single ' ' */
	Permissive_ATX_Headers     = 2,  /* Do not require space in ATX headers ( ###header ) */
	Permissive_URL_Autolinks   = 3,  /* Recognize URLs as autolinks even without '<', '>' */
	Permissive_Email_Autolinks = 4,  /* Recognize e-mails as autolinks even without '<', '>' and 'mailto:' */
	No_Indented_Code_Blocks    = 5,  /* Disable indented code blocks. (Only fenced code works.) */
	No_HTML_Blocks             = 6,  /* Disable raw HTML blocks. */
	No_HTML_Spans              = 7,  /* Disable raw HTML (inline). */
	Tables                     = 8,  /* Enable tables extension. */
	Strikethrough              = 9,  /* Enable strikethrough extension. */
	Permissive_WWW_Autolinks   = 10, /* Enable WWW autolinks (even without any scheme prefix, if they begin with 'www.') */
	Task_Lists                 = 11, /* Enable task list extension. */
	Latex_Math_Spans           = 12, /* Enable $ and $$ containing LaTeX equations. */
	Wiki_Links                 = 13, /* Enable wiki links extension. */
	Underline                  = 14, /* Enable underline extension (and disables '_' for normal emphasis). */
	Hard_Soft_Breaks           = 15, /* Force all soft breaks to act as hard breaks. */
}

Parser_Flags :: bit_set[Parser_Flag; u32]

Parser_Flags_Permissive_Auto_Links :: Parser_Flags{.Permissive_Email_Autolinks, .Permissive_URL_Autolinks, .Permissive_WWW_Autolinks}

Parser_Flags_No_HTML :: Parser_Flags{.No_HTML_Blocks, .No_HTML_Spans}

Parser_Flags_Commonmark :: Parser_Flags{}

Parser_Flags_GitHub :: Parser_Flags_Permissive_Auto_Links | {.Tables, .Task_Lists, .Strikethrough}

Error :: union #shared_nil {
	io.Error,
	runtime.Allocator_Error,
	enum u8 {
		Parser_Error = 1,
	},
}

Block_Type :: enum c.uint {
    // <body>...</body>
    Document = 0,

    // <blockquote>...</blockquote>
    Quote,

	// <ul>...</ul>
    Unordered_List,

	// <ol>...</ol>
    Ordered_List,

    // <li>...</li>
    List_Item,

    // <hr>
    Horizontal_Ruler,

    // <h1>...</h1> (for levels up to 6)
    Heading,

    // <pre><code>...</code></pre>
    Code,

    // Raw HTML block. This itself does not correspond to any particular HTML
    // tag. The contents of it _is_ raw HTML source intended to be put
    // in verbatim form to the HTML output. */
    HTML,

    // <p>...</p>
    Paragraph,

    // <table>...</table> and its contents.
    // Note all of these are used only if extension Parser_Flag.Tables is enabled.
    Table,
    Table_Head,
    Table_Body,
    Table_Row,
    Table_Header,
    Table_Data,
}

Span_Type :: enum c.int {
    // <em>...</em>
    Emphasis,

    // <strong>...</strong>
    Strong,

    // <a href="xxx">...</a>
    Anchor,

    // <img src="xxx">...</a>
    // Note: Image text can contain nested spans and even nested images.
    // If rendered into ALT attribute of HTML <IMG> tag, it's responsibility
    // of the parser to deal with it.
    Image,

    // <code>...</code>
    Code,

    // <del>...</del>
    // Note: Recognized only when Parser_Flag.Strikethrough is enabled.
    Del,

    // For recognizing inline ($) and display ($$) equations
    // Note: Recognized only when Parser_Flag.Latex_Math_Spans is enabled.
    Latex_Math,
    Latex_Math_Display,

    // Wiki links
    // Note: Recognized only when Parser_Flag.Wiki_Links is enabled.
    Wiki_Link,


    // <u>...</u>
    // Note: Recognized only when Parser_Flag.Underline is enabled.
    Underline,
}

/* Text is the actual textual contents of span. */
Text_Type :: enum c.int {
    /* Normal text. */
    Normal = 0,

    /* NULL character. CommonMark requires replacing NULL character with
     * the replacement char U+FFFD, so this allows caller to do that easily. */
    Null_Char,

    /* Line breaks.
     * Note these are not sent from blocks with verbatim output (MD_BLOCK_CODE
     * or MD_BLOCK_HTML). In such cases, '\n' is part of the text itself. */
    Hard_Break, /* <br> (hard break) */
    Soft_Break, /* '\n' in source text where it is not semantically meaningful (soft break) */

    /* Entity.
     * (a) Named entity, e.g. &nbsp; 
     *     (Note MD4C does not have a list of known entities.
     *     Anything matching the regexp /&[A-Za-z][A-Za-z0-9]{1,47};/ is
     *     treated as a named entity.)
     * (b) Numerical entity, e.g. &#1234;
     * (c) Hexadecimal entity, e.g. &#x12AB;
     *
     * As MD4C is mostly encoding agnostic, application gets the verbatim
     * entity text into the MD_PARSER::text_callback(). */
    Entity,

    /* Text in a code block (inside MD_BLOCK_CODE) or inlined code (`code`).
     * If it is inside MD_BLOCK_CODE, it includes spaces for indentation and
     * '\n' for new lines. BR and SOFTBR are not sent for this
     * kind of text. */
    Code,

    /* Text is a raw HTML. If it is contents of a raw HTML block (i.e. not
     * an inline raw HTML), then BR and SOFTBR are not used.
     * The text contains verbatim '\n' for the new lines. */
    HTML,

    /* Text is inside an equation. This is processed the same way as inlined code
     * spans (`code`). */
    Latex_Math
}

Align :: enum c.int {
    Default = 0,
    Left,
    Center,
    Right,
}

Parser :: struct {
	/* Reserved. Set to zero. */
	abi_version: u32,

	/* Dialect options. Bitmask of MD_FLAG_xxxx values. */
    flags: Parser_Flags,

    /* Caller-provided rendering callbacks. These are required to be providaded
     *
     * For some block/span types, more detailed information is provided in a
     * type-specific structure pointed by the argument 'detail'.
     *
     * The last argument of all callbacks, 'userdata', is just propagated from
     * md_parse() and is available for any use by the application.
     *
     * Note any strings provided to the callbacks as their arguments or as
     * members of any detail structure are generally not zero-terminated.
     * Application has to take the respective size information into account.
     *
     * Any rendering callback may abort further parsing of the document by
     * returning non-zero.
     */
	enter_block: proc "c" (type: Block_Type, detail: rawptr, userdata: rawptr) -> i32,
	leave_block: proc "c" (type: Block_Type, detail: rawptr, userdata: rawptr) -> i32,

	enter_span: proc "c" (type: Span_Type, detail: rawptr, userdata: rawptr) -> i32,
	leave_span: proc "c" (type: Span_Type, detail: rawptr, userdata: rawptr) -> i32,

	text: proc "c" (type: Text_Type, text: [^]c.char, size: u32, userdata: rawptr) -> i32,

    /* Debug callback. Optional (may be nil).
     *
     * If provided and something goes wrong, this function gets called.
     * This is intended for debugging and problem diagnosis for developers;
     * it is not intended to provide any errors suitable for displaying to an
     * end user.
     */
	debug_log: proc "c" (msg: cstring, userdata: rawptr),

    /* Reserved. Set to NULL.
     */
	syntax: proc "c" (),
}

Input_Process_Proc :: #type proc "c"(char: [^]c.char, size: u32, userdata: rawptr)

Renderer_Flag :: enum c.int {
	Debug,
	Verbatim_Entities,
	Skip_UTF8_BOM,
	XHTML,
}

Renderer_Flags :: bit_set[Renderer_Flag; u32]

/* String attribute.
 *
 * This wraps strings which are outside of a normal text flow and which are
 * propagated within various detailed structures, but which still may contain
 * string portions of different types like e.g. entities.
 *
 * So, for example, lets consider this image:
 *
 *     ![image alt text](http://example.org/image.png 'foo &quot; bar')
 *
 * The image alt text is propagated as a normal text via the MD_PARSER::text()
 * callback. However, the image title ('foo &quot; bar') is propagated as
 * MD_ATTRIBUTE in MD_SPAN_IMG_DETAIL::title.
 *
 * Then the attribute MD_SPAN_IMG_DETAIL::title shall provide the following:
 *  -- [0]: "foo "   (substr_types[0] == MD_TEXT_NORMAL; substr_offsets[0] == 0)
 *  -- [1]: "&quot;" (substr_types[1] == MD_TEXT_ENTITY; substr_offsets[1] == 4)
 *  -- [2]: " bar"   (substr_types[2] == MD_TEXT_NORMAL; substr_offsets[2] == 10)
 *  -- [3]: (n/a)    (n/a                              ; substr_offsets[3] == 14)
 *
 * Note that these invariants are always guaranteed:
 *  -- substr_offsets[0] == 0
 *  -- substr_offsets[LAST+1] == size
 *  -- Currently, only MD_TEXT_NORMAL, MD_TEXT_ENTITY, MD_TEXT_NULLCHAR
 *     substrings can appear. This could change only of the specification
 *     changes.
 */
Attribute :: struct {
	text: cstring,
	size: u32,
    substr_types: [^]Text_Type,
    substr_offsets: [^]u32,
}

/* Detailed info for MD_BLOCK_UL. */
Unordered_List_Detail :: struct {
    is_tight: i32, /* Non-zero if tight list, zero if loose. */
    mark: c.char,  /* Item bullet character in MarkDown source of the list, e.g. '-', '+', '*'. */
};

/* Detailed info for MD_BLOCK_OL. */
Block_Ordered_List_Detail :: struct {
    start: u32,             /* Start index of the ordered list. */
    is_tight: b32,          /* Non-zero if tight list, zero if loose. */
    mark_delimiter: c.char, /* Character delimiting the item marks in MarkDown source, e.g. '.' or ')' */
}

/* Detailed info for MD_BLOCK_LI. */
Block_List_Item_Detail :: struct {
	is_task: b32,          /* Can be non-zero only with MD_FLAG_TASKLISTS */
    task_mark: c.char,     /* If is_task, then one of 'x', 'X' or ' '. Undefined otherwise. */
    task_mark_offset: u32, /* If is_task, then offset in the input of the char between '[' and ']'. */
}

/* Detailed info for MD_BLOCK_H. */
Block_Heading_Detail :: struct {
	level: u32, /* Header level (1 - 6) */
}

/* Detailed info for MD_BLOCK_CODE. */
Block_Code_Detail :: struct {
    info: Attribute,
    lang: Attribute,
    fence_char: c.char, /* The character used for fenced code block; or zero for indented code block. */
}

/* Detailed info for MD_BLOCK_TABLE. */
Block_Table_Detail :: struct {
    col_count: u32,      /* Count of columns in the table. */
    head_row_count: u32, /* Count of rows in the table header (currently always 1) */
    body_row_count: u32, /* Count of rows in the table body */
}

/* Detailed info for MD_BLOCK_TH and MD_BLOCK_TD. */
Block_Table_Data_Detail :: struct {
    align: Align,
}

/* Detailed info for MD_SPAN_A. */
Span_Anchor_Detail :: struct {
    href: Attribute,
    title: Attribute,
    is_autolink: b32,
}

/* Detailed info for MD_SPAN_IMG. */
Span_Image_Detail :: struct {
    src: Attribute,
    title: Attribute,
}

/* Detailed info for MD_SPAN_WIKILINK. */
Span_Wiki_Link_Detail :: struct {
	target: Attribute,
}

foreign md4c {
	md_parse :: proc(text: [^]c.char, size: u32, parser: ^Parser, userdata: rawptr) -> i32 ---

	md_html :: proc(
		input: [^]c.char, size: u32,
		process_output: Input_Process_Proc, userdata: rawptr,
		parser_flags: Parser_Flags, renderer_flags: Renderer_Flags,
	) -> i32 ---
}

@private
Helper_Context :: struct {
	ctx: runtime.Context,

	builder: ^strings.Builder,
	writer: io.Writer,
	io_error: io.Error,
}

@private
html_string_callback :: proc "c" (char: [^]c.char, size: u32, userdata: rawptr){
	helper := cast(^Helper_Context)userdata
	context = helper.ctx

	data := cast([]byte)(char[:size])
	append(&helper.builder.buf, ..data)
}

@private
html_writer_callback :: proc "c" (char: [^]c.char, size: u32, userdata: rawptr){
	helper := cast(^Helper_Context)userdata
	context = helper.ctx

	data := cast([]byte)(char[:size])

	_, err := io.write(helper.writer, data)
	if helper.io_error == nil {
		helper.io_error = err
	}
}

parse :: proc(source: string, parser: ^Parser, userdata: rawptr) -> bool {
	return md_parse(raw_data(source), u32(len(source)), parser, userdata) >= 0
}

to_html_writer :: proc(source: string, w: io.Writer, parser_flags: Parser_Flags, renderer_flags := Renderer_Flags{}) -> (err: Error) {
	ctx := Helper_Context {
		ctx = context,
		writer = w,
	}

	res := md_html(raw_data(source), u32(len(source)), html_writer_callback, &ctx, parser_flags, renderer_flags)

	if res < 0 {
		err = .Parser_Error
	}
	else {
		err = ctx.io_error
	}

	return
}

to_html_builder :: proc(source: string, builder: ^strings.Builder, parser_flags: Parser_Flags, renderer_flags := Renderer_Flags{}) -> (err: Error) {
	sb : strings.Builder

	ctx := Helper_Context {
		builder = &sb,
		ctx = context,
	}

	res := md_html(raw_data(source), u32(len(source)), html_string_callback, &ctx, parser_flags, renderer_flags)

	if res < 0 {
		err = .Parser_Error
	}
	return
}

to_html_string :: proc(source: string, parser_flags: Parser_Flags, renderer_flags := Renderer_Flags{}) -> (html: string, err: Error) {
	sb : strings.Builder
	strings.builder_init_len_cap(&sb, 0, len(source)) or_return

	err = to_html_builder(source, &sb, parser_flags, renderer_flags)
	html = string(sb.buf[:])

	return 
}

to_html :: proc {
	to_html_builder,
	to_html_string,
	to_html_writer,
}


