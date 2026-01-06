package FracturedJson::TableColumnType;
use strict;
use warnings;
use Exporter 'import';

our @EXPORT_OK = qw(Unknown Simple Number Array Object Mixed);
use constant {
    Unknown => 0,
    Simple  => 1,
    Number  => 2,
    Array   => 3,
    Object  => 4,
    Mixed   => 5,
};

1;
