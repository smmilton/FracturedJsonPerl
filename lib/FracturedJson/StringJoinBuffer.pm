package FracturedJson::StringJoinBuffer;
use strict;
use warnings;

sub new {
    my ($class) = @_;
    my $self = {
        linebuff => [],
        docbuff  => [],
    };
    bless $self, $class;
    return $self;
}

sub Add {
    my ($self, @vals) = @_;
    push @{ $self->{linebuff} }, @vals;
    return $self;
}

sub Spaces {
    my ($self, $count) = @_;
    $count ||= 0;
    $count = 0 if $count < 0;
    my $spaces = ($count < 64) ? (' ' x $count) : (' ' x $count);
    push @{ $self->{linebuff} }, $spaces;
    return $self;
}

sub EndLine {
    my ($self, $eol) = @_;
    $self->_AddLineToWriter($eol // "");
    return $self;
}

sub Flush {
    my ($self) = @_;
    $self->_AddLineToWriter("");
    return $self;
}

sub AsString {
    my ($self) = @_;
    return join('', @{ $self->{docbuff} });
}

sub _AddLineToWriter {
    my ($self, $eol) = @_;
    $eol //= '';
    return if (!@{ $self->{linebuff} } && length($eol)==0);
    my $line = join('', @{ $self->{linebuff} });
    $line =~ s/[\s\t]+$//; # trim end whitespace
    push @{ $self->{docbuff} }, $line . $eol;
    $self->{linebuff} = [];
}

1;
