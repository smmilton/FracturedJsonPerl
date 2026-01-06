package FracturedJson::TokenEnumerator;
use strict;
use warnings;
use FracturedJson::Error;

sub new {
    my ($class, $tokens) = @_;
    $tokens ||= [];
    my $self = {
        tokens => $tokens,
        idx => -1,
        current => undef,
    };
    bless $self, $class;
    return $self;
}

sub Current {
    my ($self) = @_;
    die FracturedJson::Error->new('Illegal enumerator usage') if !defined $self->{current};
    return $self->{current};
}

sub MoveNext {
    my ($self) = @_;
    $self->{idx} += 1;
    if ($self->{idx} < @{ $self->{tokens} }) {
        $self->{current} = $self->{tokens}->[$self->{idx}];
        return 1;
    }
    $self->{current} = undef;
    return 0;
}

1;
