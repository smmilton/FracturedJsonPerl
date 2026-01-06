# FracturedJson (Perl)

Pure-Perl port of the FracturedJson formatter.

## Usage

### Library

```perl
use FracturedJson::Formatter;

my $formatter = FracturedJson::Formatter->new();
my $out = $formatter->Reformat($json_text, 0);
```

### CLI

```sh
fjson file.json
fjson --minify file.json
cat file.jsonc | fjson --preserve-comments
```

## Authors

- Original author: https://github.com/j-brooke
- Perl port: https://github.com/smmilton

## License

MIT License. See `LICENSE`.
