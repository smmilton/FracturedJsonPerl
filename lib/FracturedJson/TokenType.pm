package FracturedJson::TokenType;
use strict;
use warnings;
use Exporter 'import';

our @EXPORT_OK = qw(Invalid BeginArray EndArray BeginObject EndObject String Number Null True False BlockComment LineComment BlankLine Comma Colon);
use constant {
    Invalid      => 0,
    BeginArray   => 1,
    EndArray     => 2,
    BeginObject  => 3,
    EndObject    => 4,
    String       => 5,
    Number       => 6,
    Null         => 7,
    True         => 8,
    False        => 9,
    BlockComment => 10,
    LineComment  => 11,
    BlankLine    => 12,
    Comma        => 13,
    Colon        => 14,
};

1;
