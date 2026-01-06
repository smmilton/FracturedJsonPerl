package FracturedJson::InputPosition;
use strict;
use warnings;
use Exporter 'import';
our @EXPORT_OK = qw(new_pos clone_pos);

sub new_pos {
    my ($idx,$row,$col) = @_;
    return { Index => $idx // 0, Row => $row // 0, Column => $col // 0 };
}

sub clone_pos {
    my ($pos) = @_;
    return { Index => $pos->{Index}, Row => $pos->{Row}, Column => $pos->{Column} };
}

1;
