package FracturedJson::BracketPaddingType;
use strict;
use warnings;
use Exporter 'import';

our @EXPORT_OK = qw(Empty Simple Complex);
use constant {
    Empty   => 0,
    Simple  => 1,
    Complex => 2,
};

1;
