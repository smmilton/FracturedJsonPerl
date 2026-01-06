package FracturedJson::JsonToken;
use strict;
use warnings;
use Exporter 'import';
our @EXPORT_OK = qw(make_token);
use FracturedJson::InputPosition qw(clone_pos);

sub make_token {
    my ($type, $text, $pos) = @_;
    return {
        Type => $type,
        Text => $text,
        InputPosition => clone_pos($pos),
    };
}

1;
