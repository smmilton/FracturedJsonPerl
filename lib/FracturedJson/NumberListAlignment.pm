package FracturedJson::NumberListAlignment;
use strict;
use warnings;
use Exporter 'import';

our @EXPORT_OK = qw(Left Right Decimal Normalize);
use constant {
    Left      => 0,
    Right     => 1,
    Decimal   => 2,
    Normalize => 3,
};

1;
