package FracturedJson::Error;
use strict;
use warnings;
use overload ('""' => 'message');

sub new {
    my ($class, $message, $pos) = @_;
    my $msg_with_pos = defined $pos
        ? sprintf('%s at idx=%d, row=%d, col=%d', ($message//''), $pos->{Index}//0, $pos->{Row}//0, $pos->{Column}//0)
        : ($message // '');
    my $self = {
        message => $msg_with_pos,
        InputPosition => $pos,
    };
    bless $self, $class;
    return $self;
}

sub message {
    my ($self) = @_;
    return $self->{message};
}

1;
