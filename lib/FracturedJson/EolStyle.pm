package FracturedJson::EolStyle;
use strict;
use warnings;
use Exporter 'import';

our @EXPORT_OK = qw(Lf Crlf);
use constant {
    Lf   => 0,
    Crlf => 1,
};

1;
