package FracturedJson::TableCommaPlacement;
use strict;
use warnings;
use Exporter 'import';

our @EXPORT_OK = qw(BeforePadding BeforePaddingExceptNumbers AfterPadding);
use constant {
    BeforePadding             => 0,
    BeforePaddingExceptNumbers=> 1,
    AfterPadding              => 2,
};

1;
