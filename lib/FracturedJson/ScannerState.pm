package FracturedJson::ScannerState;
use strict;
use warnings;
use FracturedJson::Error;
use FracturedJson::InputPosition qw(new_pos clone_pos);
use constant MaxDocSize => 2000000000;

sub new {
    my ($class, $text) = @_;
    my $self = {
        _originalText => $text // '',
        CurrentPosition => { Index => 0, Row => 0, Column => 0 },
        TokenPosition => { Index => 0, Row => 0, Column => 0 },
        NonWhitespaceSinceLastNewline => 0,
    };
    bless $self, $class;
    return $self;
}

sub Advance {
    my ($self, $is_whitespace) = @_;
    die 'Maximum document length exceeded' if $self->{CurrentPosition}->{Index} >= MaxDocSize;
    $self->{CurrentPosition}->{Index} += 1;
    $self->{CurrentPosition}->{Column} += 1;
    $self->{NonWhitespaceSinceLastNewline} ||= !$is_whitespace;
}

sub NewLine {
    my ($self) = @_;
    die 'Maximum document length exceeded' if $self->{CurrentPosition}->{Index} >= MaxDocSize;
    $self->{CurrentPosition}->{Index} += 1;
    $self->{CurrentPosition}->{Row} += 1;
    $self->{CurrentPosition}->{Column} = 0;
    $self->{NonWhitespaceSinceLastNewline} = 0;
}

sub SetTokenStart {
    my ($self) = @_;
    $self->{TokenPosition} = { %{ $self->{CurrentPosition} } };
}

sub MakeTokenFromBuffer {
    my ($self, $type, $trim_end) = @_;
    my $start = $self->{TokenPosition}->{Index};
    my $end = $self->{CurrentPosition}->{Index};
    my $substring = substr($self->{_originalText}, $start, $end - $start);
    $substring =~ s/\s+$// if $trim_end;
    return {
        Type => $type,
        Text => $substring,
        InputPosition => { %{ $self->{TokenPosition} } },
    };
}

sub MakeToken {
    my ($self, $type, $text) = @_;
    return {
        Type => $type,
        Text => $text,
        InputPosition => { %{ $self->{TokenPosition} } },
    };
}

sub Current {
    my ($self) = @_;
    return undef if $self->AtEnd;
    return ord(substr($self->{_originalText}, $self->{CurrentPosition}->{Index}, 1));
}

sub AtEnd {
    my ($self) = @_;
    return $self->{CurrentPosition}->{Index} >= length($self->{_originalText});
}

sub Throw {
    my ($self, $message) = @_;
    die FracturedJson::Error->new($message, { %{ $self->{CurrentPosition} } });
}

1;
