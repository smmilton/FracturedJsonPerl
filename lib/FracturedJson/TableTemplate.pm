package FracturedJson::TableTemplate;
use strict;
use warnings;
use List::Util qw(max sum);
use FracturedJson::JsonItemType qw(Null False True String Number Object Array BlankLine LineComment BlockComment);
use FracturedJson::BracketPaddingType qw(Empty Simple Complex);
use FracturedJson::TableColumnType (); # use fully qualified to avoid collisions
use FracturedJson::NumberListAlignment qw(Left Right Decimal Normalize);

use constant {
    TC_Unknown => FracturedJson::TableColumnType::Unknown(),
    TC_Simple  => FracturedJson::TableColumnType::Simple(),
    TC_Number  => FracturedJson::TableColumnType::Number(),
    TC_Array   => FracturedJson::TableColumnType::Array(),
    TC_Object  => FracturedJson::TableColumnType::Object(),
    TC_Mixed   => FracturedJson::TableColumnType::Mixed(),
};

sub new {
    my ($class, $pads, $number_align) = @_;
    my $self = {
        LocationInParent => undef,
        Type => TC_Unknown,
        RowCount => 0,
        NameLength => 0,
        NameMinimum => 9**9, # large sentinel
        MaxValueLength => 0,
        MaxAtomicValueLength => 0,
        PrefixCommentLength => 0,
        MiddleCommentLength => 0,
        AnyMiddleCommentHasNewline => 0,
        PostfixCommentLength => 0,
        IsAnyPostCommentLineStyle => 0,
        PadType => Simple,
        RequiresMultipleLines => 0,
        CompositeValueLength => 0,
        TotalLength => 0,
        ShorterThanNullAdjustment => 0,
        ContainsNull => 0,
        Children => [],
        _pads => $pads,
        _numberListAlignment => $number_align,
        _maxDigBeforeDec => 0,
        _maxDigAfterDec => 0,
    };
    bless $self, $class;
    return $self;
}

sub MeasureTableRoot {
    my ($self, $tableRoot, $recursive) = @_;
    foreach my $child (@{ $tableRoot->{Children} }) {
        $self->_MeasureRowSegment($child, $recursive);
    }
    $self->_PruneAndRecompute(9**9);
}

sub TryToFit {
    my ($self, $maximumLength) = @_;
    my $complexity = $self->_GetTemplateComplexity();
    while (1) {
        return 1 if $self->{TotalLength} <= $maximumLength;
        return 0 if $complexity <= 0;
        $complexity -= 1;
        $self->_PruneAndRecompute($complexity);
    }
}

sub FormatNumber {
    my ($self, $buffer, $item, $commaBeforePad) = @_;
    if ($self->{_numberListAlignment} == Left) {
        $buffer->Add($item->{Value}, $commaBeforePad)->Spaces($self->{MaxValueLength} - $item->{ValueLength});
        return;
    }
    if ($self->{_numberListAlignment} == Right) {
        $buffer->Spaces($self->{MaxValueLength} - $item->{ValueLength})->Add($item->{Value}, $commaBeforePad);
        return;
    }

    if ($item->{Type} == Null) {
        $buffer->Spaces($self->{_maxDigBeforeDec} - $item->{ValueLength})
            ->Add($item->{Value}, $commaBeforePad)
            ->Spaces($self->{CompositeValueLength} - $self->{_maxDigBeforeDec});
        return;
    }

    if ($self->{_numberListAlignment} == Normalize) {
        my $parsed = $item->{Value} + 0;
        my $reformatted = sprintf('%.*f', $self->{_maxDigAfterDec}, $parsed);
        $buffer->Spaces($self->{CompositeValueLength} - length($reformatted))->Add($reformatted, $commaBeforePad);
        return;
    }

    my ($leftPad, $rightPad);
    my $val = $item->{Value};
    my $idx = ($val =~ /[.eE]/) ? index($val, ($val =~ /[eE]/ ? ($val =~ /e/ ? 'e' : 'E') : '.')) : -1;
    if ($idx > 0) {
        $leftPad = $self->{_maxDigBeforeDec} - $idx;
        $rightPad = $self->{CompositeValueLength} - $leftPad - $item->{ValueLength};
    } else {
        $leftPad = $self->{_maxDigBeforeDec} - $item->{ValueLength};
        $rightPad = $self->{CompositeValueLength} - $self->{_maxDigBeforeDec};
    }
    $buffer->Spaces($leftPad)->Add($item->{Value}, $commaBeforePad)->Spaces($rightPad);
}

sub AtomicItemSize {
    my ($self) = @_;
    my $pads = $self->{_pads};
    return $self->{NameLength}
        + $pads->ColonLen
        + $self->{MiddleCommentLength}
        + (($self->{MiddleCommentLength} > 0) ? $pads->CommentLen : 0)
        + $self->{MaxAtomicValueLength}
        + $self->{PostfixCommentLength}
        + (($self->{PostfixCommentLength} > 0) ? $pads->CommentLen : 0)
        + $pads->CommaLen;
}

sub _MeasureRowSegment {
    my ($self, $rowSegment, $recursive) = @_;
    if ($rowSegment->{Type} == BlankLine || $rowSegment->{Type} == BlockComment || $rowSegment->{Type} == LineComment) {
        return;
    }

    my $rowTableType;
    if ($rowSegment->{Type} == Null) {
        $rowTableType = TC_Unknown;
    } elsif ($rowSegment->{Type} == Number) {
        $rowTableType = TC_Number;
    } elsif ($rowSegment->{Type} == Array) {
        $rowTableType = TC_Array;
    } elsif ($rowSegment->{Type} == Object) {
        $rowTableType = TC_Object;
    } else {
        $rowTableType = TC_Simple;
    }

    if ($self->{Type} == TC_Unknown) {
        $self->{Type} = $rowTableType;
    } elsif ($rowTableType != TC_Unknown && $self->{Type} != $rowTableType) {
        $self->{Type} = TC_Mixed;
    }

    if ($rowSegment->{Type} == Null) {
        $self->{_maxDigBeforeDec} = max($self->{_maxDigBeforeDec}, $self->{_pads}->LiteralNullLen);
        $self->{ContainsNull} = 1;
    }

    if ($rowSegment->{RequiresMultipleLines}) {
        $self->{RequiresMultipleLines} = 1;
        $self->{Type} = TC_Mixed;
    }

    $self->{RowCount} += 1;
    $self->{NameLength} = max($self->{NameLength}, $rowSegment->{NameLength});
    $self->{NameMinimum} = ($self->{NameMinimum} < $rowSegment->{NameLength}) ? $self->{NameMinimum} : $rowSegment->{NameLength};
    $self->{MaxValueLength} = max($self->{MaxValueLength}, $rowSegment->{ValueLength});
    $self->{MiddleCommentLength} = max($self->{MiddleCommentLength}, $rowSegment->{MiddleCommentLength});
    $self->{PrefixCommentLength} = max($self->{PrefixCommentLength}, $rowSegment->{PrefixCommentLength});
    $self->{PostfixCommentLength} = max($self->{PostfixCommentLength}, $rowSegment->{PostfixCommentLength});
    $self->{IsAnyPostCommentLineStyle} ||= $rowSegment->{IsPostCommentLineStyle};
    $self->{AnyMiddleCommentHasNewline} ||= $rowSegment->{MiddleCommentHasNewLine};

    if ($rowSegment->{Type} != Array && $rowSegment->{Type} != Object) {
        $self->{MaxAtomicValueLength} = max($self->{MaxAtomicValueLength}, $rowSegment->{ValueLength});
    }
    if ($rowSegment->{Complexity} >= 2) {
        $self->{PadType} = Complex;
    }

    if ($self->{RequiresMultipleLines} || $rowSegment->{Type} == Null) {
        return;
    }

    if ($self->{Type} == TC_Array && $recursive) {
        for (my $i = 0; $i < @{ $rowSegment->{Children} }; ++$i) {
            if ($#{ $self->{Children} } < $i) {
                push @{ $self->{Children} }, FracturedJson::TableTemplate->new($self->{_pads}, $self->{_numberListAlignment});
            }
            $self->{Children}->[$i]->_MeasureRowSegment($rowSegment->{Children}->[$i], 1);
        }
    }
    elsif ($self->{Type} == TC_Object && $recursive) {
        if (_ContainsDuplicateKeys($rowSegment->{Children})) {
            $self->{Type} = TC_Simple;
            return;
        }
        foreach my $rowSegChild (@{ $rowSegment->{Children} }) {
            my ($subTemplate) = grep { defined $_->{LocationInParent} && $_->{LocationInParent} eq $rowSegChild->{Name} } @{ $self->{Children} };
            if (!$subTemplate) {
                $subTemplate = FracturedJson::TableTemplate->new($self->{_pads}, $self->{_numberListAlignment});
                $subTemplate->{LocationInParent} = $rowSegChild->{Name};
                push @{ $self->{Children} }, $subTemplate;
            }
            $subTemplate->_MeasureRowSegment($rowSegChild, 1);
        }
    }

    my $skipDecimal = $self->{Type} != TC_Number || $self->{_numberListAlignment} == Left || $self->{_numberListAlignment} == Right;
    return if $skipDecimal;

    my $normalizedStr = $rowSegment->{Value};
    if ($self->{_numberListAlignment} == Normalize) {
        my $parsedVal = $normalizedStr + 0;
        $normalizedStr = "$parsedVal";
        my $canNormalize = ($normalizedStr ne 'nan' && $normalizedStr ne 'inf' && $normalizedStr ne '-inf'
            && length($normalizedStr) <= 16 && index($normalizedStr, 'e') < 0
            && ($parsedVal != 0 || ($rowSegment->{Value} =~ /^-?[0.]+([eE].*)?$/)));
        if (!$canNormalize) {
            $self->{_numberListAlignment} = Left;
            return;
        }
    }

    my $indexOfDot = ($normalizedStr =~ /[.eE]/) ? (index($normalizedStr, ($normalizedStr =~ /e/ ? 'e' : ($normalizedStr =~ /E/ ? 'E' : '.')))) : -1;
    my $beforeDec = ($indexOfDot >= 0) ? $indexOfDot : length($normalizedStr);
    my $afterDec = ($indexOfDot >= 0) ? (length($normalizedStr) - $indexOfDot - 1) : 0;
    $self->{_maxDigBeforeDec} = max($self->{_maxDigBeforeDec}, $beforeDec);
    $self->{_maxDigAfterDec} = max($self->{_maxDigAfterDec}, $afterDec);
}

sub _PruneAndRecompute {
    my ($self, $maxAllowedComplexity) = @_;
    my $clearChildren = ($maxAllowedComplexity <= 0 || ($self->{Type} != TC_Array && $self->{Type} != TC_Object) || $self->{RowCount} < 2);
    if ($clearChildren) {
        $self->{Children} = [];
    }

    foreach my $sub (@{ $self->{Children} }) {
        $sub->_PruneAndRecompute($maxAllowedComplexity - 1);
    }

    if ($self->{Type} == TC_Number) {
        $self->{CompositeValueLength} = $self->_GetNumberFieldWidth();
    }
    elsif (@{ $self->{Children} } > 0) {
        my $totalChildLen = 0;
        $totalChildLen += $_->{TotalLength} for @{ $self->{Children} };
        $self->{CompositeValueLength} = $totalChildLen
            + max(0, $self->{_pads}->CommaLen * (@{ $self->{Children} } - 1))
            + $self->{_pads}->ArrStartLen($self->{PadType})
            + $self->{_pads}->ArrEndLen($self->{PadType});
        if ($self->{ContainsNull} && $self->{CompositeValueLength} < $self->{_pads}->LiteralNullLen) {
            $self->{ShorterThanNullAdjustment} = $self->{_pads}->LiteralNullLen - $self->{CompositeValueLength};
            $self->{CompositeValueLength} = $self->{_pads}->LiteralNullLen;
        }
    }
    else {
        $self->{CompositeValueLength} = $self->{MaxValueLength};
    }

    $self->{TotalLength} =
        (($self->{PrefixCommentLength} > 0) ? $self->{PrefixCommentLength} + $self->{_pads}->CommentLen : 0)
        + (($self->{NameLength} > 0) ? $self->{NameLength} + $self->{_pads}->ColonLen : 0)
        + (($self->{MiddleCommentLength} > 0) ? $self->{MiddleCommentLength} + $self->{_pads}->CommentLen : 0)
        + $self->{CompositeValueLength}
        + (($self->{PostfixCommentLength} > 0) ? $self->{PostfixCommentLength} + $self->{_pads}->CommentLen : 0);
}

sub _GetTemplateComplexity {
    my ($self) = @_;
    return 0 if @{ $self->{Children} } == 0;
    my $max_child = 0;
    foreach my $ch (@{ $self->{Children} }) {
        $max_child = max($max_child, $ch->_GetTemplateComplexity());
    }
    return 1 + $max_child;
}

sub _GetNumberFieldWidth {
    my ($self) = @_;
    if ($self->{_numberListAlignment} == Normalize || $self->{_numberListAlignment} == Decimal) {
        my $rawDecLen = ($self->{_maxDigAfterDec} > 0) ? 1 : 0;
        return $self->{_maxDigBeforeDec} + $rawDecLen + $self->{_maxDigAfterDec};
    }
    return $self->{MaxValueLength};
}

sub _ContainsDuplicateKeys {
    my ($list) = @_;
    my %seen;
    foreach my $item (@$list) {
        return 1 if $seen{$item->{Name}};
        $seen{$item->{Name}} = 1;
    }
    return 0;
}

1;
