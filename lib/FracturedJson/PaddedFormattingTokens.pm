package FracturedJson::PaddedFormattingTokens;
use strict;
use warnings;
use FracturedJson::BracketPaddingType qw(Empty Simple Complex);
use FracturedJson::EolStyle qw(Crlf);
use FracturedJson::JsonItemType qw(Array Object);

sub new {
    my ($class, $opts, $len_func) = @_;
    $len_func ||= sub { length($_[0] // '') };

    my $self = bless {}, $class;

    $self->{_arrStart} = [];
    $self->{_arrStart}->[Empty]   = '[';
    $self->{_arrStart}->[Simple]  = ($opts->{SimpleBracketPadding}) ? '[ ' : '[';
    $self->{_arrStart}->[Complex] = ($opts->{NestedBracketPadding}) ? '[ ' : '[';

    $self->{_arrEnd} = [];
    $self->{_arrEnd}->[Empty]   = ']';
    $self->{_arrEnd}->[Simple]  = ($opts->{SimpleBracketPadding}) ? ' ]' : ']';
    $self->{_arrEnd}->[Complex] = ($opts->{NestedBracketPadding}) ? ' ]' : ']';

    $self->{_objStart} = [];
    $self->{_objStart}->[Empty]   = '{';
    $self->{_objStart}->[Simple]  = ($opts->{SimpleBracketPadding}) ? '{ ' : '{';
    $self->{_objStart}->[Complex] = ($opts->{NestedBracketPadding}) ? '{ ' : '{';

    $self->{_objEnd} = [];
    $self->{_objEnd}->[Empty]   = '}';
    $self->{_objEnd}->[Simple]  = ($opts->{SimpleBracketPadding}) ? ' }' : '}';
    $self->{_objEnd}->[Complex] = ($opts->{NestedBracketPadding}) ? ' }' : '}';

    $self->{_comma} = ($opts->{CommaPadding}) ? ', ' : ',';
    $self->{_colon} = ($opts->{ColonPadding}) ? ': ' : ':';
    $self->{_comment} = ($opts->{CommentPadding}) ? ' ' : '';
    $self->{_eol} = ($opts->{JsonEolStyle} == Crlf) ? "\r\n" : "\n";

    $self->{_arrStartLen} = [ map { $len_func->($_) } @{ $self->{_arrStart} } ];
    $self->{_arrEndLen}   = [ map { $len_func->($_) } @{ $self->{_arrEnd} } ];
    $self->{_objStartLen} = [ map { $len_func->($_) } @{ $self->{_objStart} } ];
    $self->{_objEndLen}   = [ map { $len_func->($_) } @{ $self->{_objEnd} } ];

    $self->{_indentStrings} = [
        '',
        ($opts->{UseTabToIndent} ? "\t" : ' ' x $opts->{IndentSpaces})
    ];

    $self->{_commaLen} = $len_func->($self->{_comma});
    $self->{_colonLen} = $len_func->($self->{_colon});
    $self->{_commentLen} = $len_func->($self->{_comment});
    $self->{_literalNullLen}  = $len_func->('null');
    $self->{_literalTrueLen}  = $len_func->('true');
    $self->{_literalFalseLen} = $len_func->('false');
    $self->{_prefixStringLen} = $len_func->($opts->{PrefixString});
    $self->{_dummyComma} = ' ' x $self->{_commaLen};

    return $self;
}

sub Comma { $_[0]->{_comma} }
sub Colon { $_[0]->{_colon} }
sub Comment { $_[0]->{_comment} }
sub EOL { $_[0]->{_eol} }
sub DummyComma { $_[0]->{_dummyComma} }
sub CommaLen { $_[0]->{_commaLen} }
sub ColonLen { $_[0]->{_colonLen} }
sub CommentLen { $_[0]->{_commentLen} }
sub LiteralNullLen { $_[0]->{_literalNullLen} }
sub LiteralTrueLen { $_[0]->{_literalTrueLen} }
sub LiteralFalseLen { $_[0]->{_literalFalseLen} }
sub PrefixStringLen { $_[0]->{_prefixStringLen} }

sub ArrStart { $_[0]->{_arrStart}->[$_[1]] }
sub ArrEnd { $_[0]->{_arrEnd}->[$_[1]] }
sub ObjStart { $_[0]->{_objStart}->[$_[1]] }
sub ObjEnd { $_[0]->{_objEnd}->[$_[1]] }
sub Start { my ($self,$type,$br) = @_; return ($type==Array)? $self->ArrStart($br) : $self->ObjStart($br); }
sub End { my ($self,$type,$br) = @_; return ($type==Array)? $self->ArrEnd($br) : $self->ObjEnd($br); }

sub ArrStartLen { $_[0]->{_arrStartLen}->[$_[1]] }
sub ArrEndLen { $_[0]->{_arrEndLen}->[$_[1]] }
sub ObjStartLen { $_[0]->{_objStartLen}->[$_[1]] }
sub ObjEndLen { $_[0]->{_objEndLen}->[$_[1]] }
sub StartLen { my ($self,$type,$br) = @_; return ($type==Array)? $self->ArrStartLen($br) : $self->ObjStartLen($br); }
sub EndLen { my ($self,$type,$br) = @_; return ($type==Array)? $self->ArrEndLen($br) : $self->ObjEndLen($br); }

sub Indent {
    my ($self,$level) = @_;
    $level ||= 0;
    if ($level >= @{ $self->{_indentStrings} }) {
        for (my $i=@{ $self->{_indentStrings} }; $i <= $level; ++$i) {
            $self->{_indentStrings}->[$i] = $self->{_indentStrings}->[$i-1] . $self->{_indentStrings}->[1];
        }
    }
    return $self->{_indentStrings}->[$level];
}

1;
