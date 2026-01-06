# FracturedJson (Perl)

Pure-Perl port of the FracturedJson formatter: a JSON formatter that tries to
keep related values on the same line when they fit, and “fractures” onto new
lines only when the structure gets complex or lines get too long.

- Formats JSON.
- Optionally accepts and preserves/removes JSONC-style comments (`//` and `/* */`).
- Provides a CLI (`fjson`) and a library API.

## Installation

### From source

```sh
perl Makefile.PL
make
make test
make install
```

Minimum supported Perl version is `5.10` (see `Makefile.PL`).

## Quick start

### CLI

Format a file:

```sh
fjson input.json
```

Format from STDIN:

```sh
cat input.json | fjson
```

Minify:

```sh
fjson --minify input.json
```

Allow JSONC comments and keep them:

```sh
fjson --preserve-comments input.jsonc
```

Allow JSONC comments but strip them:

```sh
fjson --remove-comments input.jsonc
```

### Library

```perl
use strict;
use warnings;

use FracturedJson::Formatter;
use FracturedJson::Options;

my $formatter = FracturedJson::Formatter->new();
$formatter->{Options} = FracturedJson::Options->new({
    MaxTotalLineLength => 100,
    IndentSpaces       => 2,
});

my $pretty = $formatter->Reformat('{"a":1,"b":[2,3]}', 0);
print $pretty;
```

## CLI reference (`fjson`)

`fjson [options] [file ...]`

If no files are provided, `fjson` reads from STDIN. Output is written to STDOUT.

### Options

- `--minify`
  - Writes compact JSON (no extra spaces/newlines).
- `--preserve-comments`
  - Accepts JSONC comments and preserves them in output.
- `--remove-comments`
  - Accepts JSONC comments and strips them in output.
- `--allow-trailing-commas`
  - Accepts trailing commas in arrays/objects.
- `--preserve-blank-lines`
  - Preserves blank lines from the input (only meaningful when comments are
    preserved, or when input contains blank lines and you want to keep them).
- `--crlf`
  - Writes CRLF line endings (default is LF).
- `--indent-spaces N`
  - Sets indent width (default `4`).
- `--max-line-length N`
  - Sets maximum line length used when deciding whether inline/table formatting
    fits (default `120`).
- `--always-expand-depth N`
  - Controls when the formatter stops trying inline/compact forms.
  - Default `-1` (meaning “try inline/compact whenever possible”).
- `-h`, `--help`
  - Show help.

## Library API

### `FracturedJson::Formatter`

Create a formatter:

```perl
my $formatter = FracturedJson::Formatter->new();
```

Attach options (recommended):

```perl
use FracturedJson::Options;
$formatter->{Options} = FracturedJson::Options->new({
    MaxTotalLineLength => 120,
    IndentSpaces       => 4,
});
```

Format JSON text:

```perl
my $out = $formatter->Reformat($json_text, $starting_depth);
```

- `$starting_depth` is usually `0`. It is useful if you’re embedding formatted
  JSON inside an already-indented context.

Minify JSON text:

```perl
my $min = $formatter->Minify($json_text);
```

### Errors

On parse/format errors, the library throws `FracturedJson::Error`. When
stringified it includes position information (index/row/column).

The CLI wraps errors and exits non-zero.

## Options (`FracturedJson::Options`)

`FracturedJson::Options->new()` returns an object with defaults.

You can override options by passing a hashref:

```perl
use FracturedJson::Options;

my $opts = FracturedJson::Options->new({
    MaxTotalLineLength => 100,
    IndentSpaces       => 2,
});
```

### Full options table

Defaults below are from `FracturedJson::Options->new()`.

| Option | Default | Meaning |
|---|---:|---|
| `JsonEolStyle` | `Lf` | Output newline style. Use `FracturedJson::EolStyle` constants `Lf` or `Crlf`. |
| `MaxTotalLineLength` | `120` | Target maximum line length for decisions like “can this fit inline?”. |
| `MaxInlineComplexity` | `2` | Maximum “complexity” allowed for fully-inline containers (arrays/objects). Lower means more line breaks. |
| `MaxCompactArrayComplexity` | `2` | Maximum complexity for “compact multiline array” layout. |
| `MaxTableRowComplexity` | `2` | Maximum complexity for table-style formatting (rows aligned in columns). |
| `MaxPropNamePadding` | `16` | Maximum extra padding allowed when aligning object property names. |
| `ColonBeforePropNamePadding` | `0` | If true, aligns as `"key":<spaces> value` instead of `"key"<spaces>: value` (mainly affects aligned object formatting). |
| `TableCommaPlacement` | `BeforePaddingExceptNumbers` | Where commas are placed relative to padding in table output. Use `FracturedJson::TableCommaPlacement` constants. |
| `MinCompactArrayRowItems` | `3` | Minimum number of array items required before compact-multiline array formatting is considered. |
| `AlwaysExpandDepth` | `-1` | Depth threshold to force expanded formatting. Higher values make deeper structures expand earlier. `-1` tries compact formats whenever possible. |
| `NestedBracketPadding` | `1` | If true, adds spaces inside brackets/braces for “complex” (nested) containers. |
| `SimpleBracketPadding` | `0` | If true, adds spaces inside brackets/braces for “simple” containers. |
| `ColonPadding` | `1` | If true, uses `": "` between key and value; otherwise `":"`. |
| `CommaPadding` | `1` | If true, uses `", "` after commas; otherwise `","`. |
| `CommentPadding` | `1` | If true, inserts a space before comments when attached inline. |
| `NumberListAlignment` | `Decimal` | Numeric column alignment in table formatting. Use `FracturedJson::NumberListAlignment` constants `Left`, `Right`, `Decimal`, `Normalize`. |
| `IndentSpaces` | `4` | Number of spaces per indent level (ignored if `UseTabToIndent` is true). |
| `UseTabToIndent` | `0` | If true, indents using tabs instead of spaces. |
| `PrefixString` | `""` | Prepended to every output line (useful for comment markers or indentation prefixes). |
| `CommentPolicy` | `TreatAsError` | How to handle comments in input: reject, remove, or preserve. Use `FracturedJson::CommentPolicy` constants `TreatAsError`, `Remove`, `Preserve`. |
| `PreserveBlankLines` | `0` | If true, preserves blank lines from input (blank line tokens). |
| `AllowTrailingCommas` | `0` | If true, accepts trailing commas in arrays/objects. |

### Using enum-like options

Some options are set using exported constants:

```perl
use FracturedJson::Options;
use FracturedJson::CommentPolicy qw(Preserve);
use FracturedJson::EolStyle qw(Crlf);
use FracturedJson::NumberListAlignment qw(Decimal);
use FracturedJson::TableCommaPlacement qw(AfterPadding);

my $opts = FracturedJson::Options->new({
    CommentPolicy       => Preserve,
    JsonEolStyle         => Crlf,
    NumberListAlignment  => Decimal,
    TableCommaPlacement  => AfterPadding,
});
```

## Authors

- Original author: https://github.com/j-brooke
- Perl port: https://github.com/smmilton

## License

MIT License. See `LICENSE`.
