package FracturedJson::JsonItemType;
use strict;
use warnings;
use Exporter 'import';

our @EXPORT_OK = qw(Null False True String Number Object Array BlankLine LineComment BlockComment);
use constant {
    Null        => 0,
    False       => 1,
    True        => 2,
    String      => 3,
    Number      => 4,
    Object      => 5,
    Array       => 6,
    BlankLine   => 7,
    LineComment => 8,
    BlockComment=> 9,
};

1;
