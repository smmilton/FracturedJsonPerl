package FracturedJson::Options;
use strict;
use warnings;
use Exporter 'import';
use FracturedJson::EolStyle qw(Lf Crlf);
use FracturedJson::CommentPolicy qw(TreatAsError);
use FracturedJson::NumberListAlignment qw(Decimal);
use FracturedJson::TableCommaPlacement qw(BeforePaddingExceptNumbers);

our @EXPORT_OK = qw(new Recommended);

sub new {
    my ($class, $init) = @_;
    my $self = {
        JsonEolStyle             => Lf,
        MaxTotalLineLength       => 120,
        MaxInlineComplexity      => 2,
        MaxCompactArrayComplexity=> 2,
        MaxTableRowComplexity    => 2,
        MaxPropNamePadding       => 16,
        ColonBeforePropNamePadding => 0,
        TableCommaPlacement      => BeforePaddingExceptNumbers,
        MinCompactArrayRowItems  => 3,
        AlwaysExpandDepth        => -1,
        NestedBracketPadding     => 1,
        SimpleBracketPadding     => 0,
        ColonPadding             => 1,
        CommaPadding             => 1,
        CommentPadding           => 1,
        NumberListAlignment      => Decimal,
        IndentSpaces             => 4,
        UseTabToIndent           => 0,
        PrefixString             => "",
        CommentPolicy            => TreatAsError,
        PreserveBlankLines       => 0,
        AllowTrailingCommas      => 0,
    };
    if ($init && ref($init) eq 'HASH') {
        for my $k (keys %{$init}) {
            $self->{$k} = $init->{$k};
        }
    }
    bless $self, $class;
    return $self;
}

sub Recommended {
    return __PACKAGE__->new();
}

1;
