package FracturedJson::CommentPolicy;
use strict;
use warnings;
use Exporter 'import';

our @EXPORT_OK = qw(TreatAsError Remove Preserve);
use constant {
    TreatAsError => 0,
    Remove       => 1,
    Preserve     => 2,
};

1;
