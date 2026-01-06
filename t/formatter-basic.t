use strict;
use warnings;

use Test::More;

use FracturedJson::Formatter;

my $formatter = FracturedJson::Formatter->new();

my $pretty = $formatter->Reformat('{"a":1,"b":[2,3]}', 0);
like($pretty, qr/\n/, 'Reformat produces multiline output');
like($pretty, qr/"a"\s*:\s*1/, 'Reformat includes key/value');

my $min = $formatter->Minify("{\n  \"a\": 1,\n  \"b\": [2, 3]\n}\n");
is($min, '{"a":1,"b":[2,3]}', 'Minify strips whitespace');

done_testing;
