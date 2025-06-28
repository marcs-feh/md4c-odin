package md4c

import "base:runtime"
import "core:c"
import "core:strings"
import "core:io"

foreign import md4c "md4c.o"

Parser_Flag :: enum c.int {
	COLLAPSE_WHITESPACE        = 1,  /* In MD_TEXT_NORMAL, collapse non-trivial whitespace into single ' ' */
	PERMISSIVE_ATX_HEADERS     = 2,  /* Do not require space in ATX headers ( ###header ) */
	PERMISSIVE_URL_AUTOLINKS   = 3,  /* Recognize URLs as autolinks even without '<', '>' */
	PERMISSIVE_EMAIL_AUTOLINKS = 4,  /* Recognize e-mails as autolinks even without '<', '>' and 'mailto:' */
	NO_INDENTED_CODEBLOCKS     = 5,  /* Disable indented code blocks. (Only fenced code works.) */
	NO_HTML_BLOCKS             = 6,  /* Disable raw HTML blocks. */
	NO_HTML_SPANS              = 7,  /* Disable raw HTML (inline). */
	TABLES                     = 8,  /* Enable tables extension. */
	STRIKETHROUGH              = 9,  /* Enable strikethrough extension. */
	PERMISSIVE_WWW_AUTOLINKS   = 10, /* Enable WWW autolinks (even without any scheme prefix, if they begin with 'www.') */
	TASK_LISTS                 = 11, /* Enable task list extension. */
	LATEXMATHSPANS             = 12, /* Enable $ and $$ containing LaTeX equations. */
	WIKI_LINKS                 = 13, /* Enable wiki links extension. */
	UNDERLINE                  = 14, /* Enable underline extension (and disables '_' for normal emphasis). */
	HARD_SOFT_BREAKS           = 15, /* Force all soft breaks to act as hard breaks. */
}

Parser_Flags :: bit_set[Parser_Flag; u32]

Parser_Flags_Permissive_Auto_Links :: Parser_Flags{.PERMISSIVE_EMAIL_AUTOLINKS, .PERMISSIVE_URL_AUTOLINKS, .PERMISSIVE_WWW_AUTOLINKS}

Parser_Flags_No_HTML :: Parser_Flags{.NO_HTML_BLOCKS, .NO_HTML_SPANS}

Parser_Flags_Commonmark :: Parser_Flags{}

Parser_Flags_GitHub :: Parser_Flags_Permissive_Auto_Links | {.TABLES, .TASK_LISTS, .STRIKETHROUGH}

Error :: union #shared_nil {
	io.Error,
	runtime.Allocator_Error,
	enum u8 {
		Parser_Error = 1,
	},
}

Block_Type :: enum c.uint {
    /* <body>...</body> */
    DOC = 0,

    /* <blockquote>...</blockquote> */
    QUOTE,

    /* <ul>...</ul>
     * Detail: Structure UL_DETAIL. */
    UL,

    /* <ol>...</ol>
     * Detail: Structure OL_DETAIL. */
    OL,

    /* <li>...</li>
     * Detail: Structure LI_DETAIL. */
    LI,

    /* <hr> */
    HR,

    /* <h1>...</h1> (for levels up to 6)
     * Detail: Structure H_DETAIL. */
    H,

    /* <pre><code>...</code></pre>
     * Note the text lines within code blocks are terminated with '\n'
     * instead of explicit MD_TEXT_BR. */
    CODE,

    /* Raw HTML block. This itself does not correspond to any particular HTML
     * tag. The contents of it _is_ raw HTML source intended to be put
     * in verbatim form to the HTML output. */
    HTML,

    /* <p>...</p> */
    P,

    /* <table>...</table> and its contents.
     * Detail: Structure TABLE_DETAIL (for TABLE),
     *         structure TD_DETAIL (for TH and TD)
     * Note all of these are used only if extension MD_FLAG_TABLES is enabled. */
    TABLE,
    THEAD,
    TBODY,
    TR,
    TH,
    TD

}

Span_Type :: enum c.int {
    /* <em>...</em> */
    EM,

    /* <strong>...</strong> */
    STRONG,

    /* <a href="xxx">...</a>
     * Detail: Structure A_DETAIL. */
    A,

    /* <img src="xxx">...</a>
     * Detail: Structure IMG_DETAIL.
     * Note: Image text can contain nested spans and even nested images.
     * If rendered into ALT attribute of HTML <IMG> tag, it's responsibility
     * of the parser to deal with it.
     */
    IMG,

    /* <code>...</code> */
    CODE,

    /* <del>...</del>
     * Note: Recognized only when MD_FLAG_STRIKETHROUGH is enabled.
     */
    DEL,

    /* For recognizing inline ($) and display ($$) equations
     * Note: Recognized only when MD_FLAG_LATEXMATHSPANS is enabled.
     */
    LATEXMATH,
    LATEXMATH_DISPLAY,

    /* Wiki links
     * Note: Recognized only when MD_FLAG_WIKILINKS is enabled.
     */
    WIKILINK,

    /* <u>...</u>
     * Note: Recognized only when MD_FLAG_UNDERLINE is enabled. */
    U,
}

/* Text is the actual textual contents of span. */
Text_Type :: enum c.int {
    /* Normal text. */
    NORMAL = 0,

    /* NULL character. CommonMark requires replacing NULL character with
     * the replacement char U+FFFD, so this allows caller to do that easily. */
    NULLCHAR,

    /* Line breaks.
     * Note these are not sent from blocks with verbatim output (MD_BLOCK_CODE
     * or MD_BLOCK_HTML). In such cases, '\n' is part of the text itself. */
    BR,         /* <br> (hard break) */
    SOFTBR,     /* '\n' in source text where it is not semantically meaningful (soft break) */

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
    ENTITY,

    /* Text in a code block (inside MD_BLOCK_CODE) or inlined code (`code`).
     * If it is inside MD_BLOCK_CODE, it includes spaces for indentation and
     * '\n' for new lines. BR and SOFTBR are not sent for this
     * kind of text. */
    CODE,

    /* Text is a raw HTML. If it is contents of a raw HTML block (i.e. not
     * an inline raw HTML), then BR and SOFTBR are not used.
     * The text contains verbatim '\n' for the new lines. */
    HTML,

    /* Text is inside an equation. This is processed the same way as inlined code
     * spans (`code`). */
    LATEXMATH
}

Align :: enum c.int {
    DEFAULT = 0,
    LEFT,
    CENTER,
    RIGHT,
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
	DEBUG,
	VERBATIM_ENTITIES,
	SKIP_UTF8_BOM,
	XHTML,
}

Renderer_Flags :: bit_set[Renderer_Flag; u32]

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

to_html_string :: proc(source: string, parser_flags: Parser_Flags, renderer_flags := Renderer_Flags{}) -> (html: string, err: Error) {
	sb : strings.Builder
	strings.builder_init_len_cap(&sb, 0, len(source)) or_return

	ctx := Helper_Context {
		builder = &sb,
		ctx = context,
	}

	res := md_html(raw_data(source), u32(len(source)), html_string_callback, &ctx, parser_flags, renderer_flags)
	html = string(sb.buf[:])

	if res < 0 {
		err = .Parser_Error
	}

	return 
}


