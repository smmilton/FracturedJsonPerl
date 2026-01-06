package FracturedJson::JsonItem;
use strict;
use warnings;
use Exporter 'import';
use FracturedJson::JsonItemType qw(Null);
use FracturedJson::InputPosition qw(new_pos);
our @EXPORT_OK = qw(new_item);

sub new_item {
    my ($type) = @_;
    my $self = {
        Type => defined $type ? $type : Null,
        InputPosition => new_pos(0,0,0),
        Complexity => 0,
        Name => '',
        Value => '',
        PrefixComment => '',
        MiddleComment => '',
        MiddleCommentHasNewLine => 0,
        PostfixComment => '',
        IsPostCommentLineStyle => 0,
        NameLength => 0,
        ValueLength => 0,
        PrefixCommentLength => 0,
        MiddleCommentLength => 0,
        PostfixCommentLength => 0,
        MinimumTotalLength => 0,
        RequiresMultipleLines => 0,
        Children => [],
    };
    return $self;
}

1;
