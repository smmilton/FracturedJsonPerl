package FracturedJson::Formatter;
use strict;
use warnings;
use JSON::PP;
use FracturedJson::Options;
use FracturedJson::StringJoinBuffer;
use FracturedJson::PaddedFormattingTokens;
use FracturedJson::JsonItem;
use FracturedJson::JsonItemType qw(Null False True String Number Object Array BlankLine LineComment BlockComment);
use FracturedJson::BracketPaddingType qw(Empty Simple Complex);
use FracturedJson::TableTemplate;
use FracturedJson::Error;
use FracturedJson::Parser;
use FracturedJson::TableCommaPlacement qw(BeforePadding BeforePaddingExceptNumbers AfterPadding);
use FracturedJson::TableColumnType (); # use fully-qualified constants

use constant {
    TC_Unknown => FracturedJson::TableColumnType::Unknown(),
    TC_Simple  => FracturedJson::TableColumnType::Simple(),
    TC_Number  => FracturedJson::TableColumnType::Number(),
    TC_Array   => FracturedJson::TableColumnType::Array(),
    TC_Object  => FracturedJson::TableColumnType::Object(),
    TC_Mixed   => FracturedJson::TableColumnType::Mixed(),
};

sub new {
    my ($class) = @_;
    my $self = {
        Options => FracturedJson::Options->new(),
        StringLengthFunc => sub { length($_[0] // '') },
        _buffer => undef,
        _pads => undef,
    };
    bless $self, $class;
    return $self;
}

sub Reformat {
    my ($self, $jsonText, $startingDepth) = @_;
    $startingDepth ||= 0;
    my $buffer = FracturedJson::StringJoinBuffer->new();
    my $parser = FracturedJson::Parser->new();
    $parser->{Options} = $self->{Options};
    my $docModel = $parser->ParseTopLevel($jsonText, 1);
    $self->_FormatTopLevel($docModel, $startingDepth, $buffer);
    $buffer->Flush();
    return $buffer->AsString();
}

sub Serialize {
    my ($self, $element, $startingDepth, $recursionLimit) = @_;
    $startingDepth ||= 0;
    $recursionLimit ||= 100;
    # Use JSON stringify from Perl to mirror JS behavior, then reformat.
    my $json = encode_json($element);
    return $self->Reformat($json, $startingDepth);
}

sub Minify {
    my ($self, $jsonText) = @_;
    my $buffer = FracturedJson::StringJoinBuffer->new();
    my $parser = FracturedJson::Parser->new();
    $parser->{Options} = $self->{Options};
    my $docModel = $parser->ParseTopLevel($jsonText, 1);
    $self->_MinifyTopLevel($docModel, $buffer);
    $buffer->Flush();
    return $buffer->AsString();
}

sub _FormatTopLevel {
    my ($self, $docModel, $startingDepth, $buffer) = @_;
    $self->{_buffer} = $buffer;
    $self->{_pads} = FracturedJson::PaddedFormattingTokens->new($self->{Options}, $self->{StringLengthFunc});
    foreach my $item (@$docModel) {
        $self->_ComputeItemLengths($item);
        $self->_FormatItem($item, $startingDepth, 0, undef);
    }
    $self->{_buffer} = FracturedJson::StringJoinBuffer->new();
}

sub _MinifyTopLevel {
    my ($self, $docModel, $buffer) = @_;
    $self->{_buffer} = $buffer;
    $self->{_pads} = FracturedJson::PaddedFormattingTokens->new($self->{Options}, $self->{StringLengthFunc});
    my $atStart = 1;
    foreach my $item (@$docModel) {
        $atStart = $self->_MinifyItem($item, $atStart);
    }
    $self->{_buffer} = FracturedJson::StringJoinBuffer->new();
}

sub _ComputeItemLengths {
    my ($self, $item) = @_;
    my $newline = "\n";
    foreach my $child (@{ $item->{Children} }) {
        $self->_ComputeItemLengths($child);
    }
    my $pads = $self->{_pads};
    if ($item->{Type} == Null) {
        $item->{ValueLength} = $pads->LiteralNullLen;
    } elsif ($item->{Type} == True) {
        $item->{ValueLength} = $pads->LiteralTrueLen;
    } elsif ($item->{Type} == False) {
        $item->{ValueLength} = $pads->LiteralFalseLen;
    } else {
        $item->{ValueLength} = $self->{StringLengthFunc}->($item->{Value});
    }
    $item->{NameLength} = $self->{StringLengthFunc}->($item->{Name});
    $item->{PrefixCommentLength} = $self->{StringLengthFunc}->($item->{PrefixComment});
    $item->{MiddleCommentLength} = $self->{StringLengthFunc}->($item->{MiddleComment});
    $item->{PostfixCommentLength} = $self->{StringLengthFunc}->($item->{PostfixComment});
    $item->{RequiresMultipleLines} =
        _IsCommentOrBlankLine($item->{Type})
        || (grep { $_->{RequiresMultipleLines} || $_->{IsPostCommentLineStyle} } @{ $item->{Children} })
        || index($item->{PrefixComment}, $newline) >= 0
        || index($item->{MiddleComment}, $newline) >= 0
        || index($item->{PostfixComment}, $newline) >= 0
        || index($item->{Value}, $newline) >= 0;

    if ($item->{Type} == Array || $item->{Type} == Object) {
        my $padType = _GetPaddingType($item);
        my $children_sum = 0;
        $children_sum += $_->{MinimumTotalLength} for @{ $item->{Children} };
        $item->{ValueLength} =
            $pads->StartLen($item->{Type}, $padType)
            + $pads->EndLen($item->{Type}, $padType)
            + $children_sum
            + (($#{ $item->{Children} } >= 0) ? $pads->CommaLen * $#{ $item->{Children} } : 0);
    }
    $item->{MinimumTotalLength} =
        (($item->{PrefixCommentLength} > 0) ? $item->{PrefixCommentLength} + $pads->CommentLen : 0)
        + (($item->{NameLength} > 0) ? $item->{NameLength} + $pads->ColonLen : 0)
        + (($item->{MiddleCommentLength} > 0) ? $item->{MiddleCommentLength} + $pads->CommentLen : 0)
        + $item->{ValueLength}
        + (($item->{PostfixCommentLength} > 0) ? $item->{PostfixCommentLength} + $pads->CommentLen : 0);
}

sub _FormatItem {
    my ($self, $item, $depth, $includeTrailingComma, $parentTemplate) = @_;
    my $t = $item->{Type};
    if ($t == Array || $t == Object) {
        $self->_FormatContainer($item, $depth, $includeTrailingComma, $parentTemplate);
    }
    elsif ($t == BlankLine) {
        $self->_FormatBlankLine();
    }
    elsif ($t == BlockComment || $t == LineComment) {
        $self->_FormatStandaloneComment($item, $depth);
    }
    else {
        if ($item->{RequiresMultipleLines}) {
            $self->_FormatSplitKeyValue($item, $depth, $includeTrailingComma, $parentTemplate);
        }
        else {
            $self->_FormatInlineElement($item, $depth, $includeTrailingComma, $parentTemplate);
        }
    }
}

sub _FormatContainer {
    my ($self, $item, $depth, $includeTrailingComma, $parentTemplate) = @_;
    if ($depth > $self->{Options}->{AlwaysExpandDepth}) {
        if ($self->_FormatContainerInline($item, $depth, $includeTrailingComma, $parentTemplate)) {
            return;
        }
    }
    my $recursiveTemplate = ($item->{Complexity} <= $self->{Options}->{MaxCompactArrayComplexity})
        || ($item->{Complexity} <= $self->{Options}->{MaxTableRowComplexity} + 1);
    my $template = FracturedJson::TableTemplate->new($self->{_pads}, $self->{Options}->{NumberListAlignment});
    $template->MeasureTableRoot($item, $recursiveTemplate);
    if ($depth > $self->{Options}->{AlwaysExpandDepth}) {
        if ($self->_FormatContainerCompactMultiline($item, $depth, $includeTrailingComma, $template, $parentTemplate)) {
            return;
        }
    }
    if ($depth >= $self->{Options}->{AlwaysExpandDepth}) {
        if ($self->_FormatContainerTable($item, $depth, $includeTrailingComma, $template, $parentTemplate)) {
            return;
        }
    }
    $self->_FormatContainerExpanded($item, $depth, $includeTrailingComma, $template, $parentTemplate);
}

sub _FormatContainerInline {
    my ($self, $item, $depth, $includeTrailingComma, $parentTemplate) = @_;
    return 0 if $item->{RequiresMultipleLines};
    my ($prefixLength,$nameLength);
    my $pads = $self->{_pads};
    if ($parentTemplate) {
        $prefixLength = ($parentTemplate->{PrefixCommentLength} > 0) ? $parentTemplate->{PrefixCommentLength} + $pads->CommentLen : 0;
        $nameLength = ($parentTemplate->{NameLength} > 0) ? $parentTemplate->{NameLength} + $pads->ColonLen : 0;
    }
    else {
        $prefixLength = ($item->{PrefixCommentLength} > 0) ? $item->{PrefixCommentLength} + $pads->CommentLen : 0;
        $nameLength = ($item->{NameLength} > 0) ? $item->{NameLength} + $pads->ColonLen : 0;
    }
    my $lengthToConsider = $prefixLength
        + $nameLength
        + (($item->{MiddleCommentLength} > 0) ? $item->{MiddleCommentLength} + $pads->CommentLen : 0)
        + $item->{ValueLength}
        + (($item->{PostfixCommentLength} > 0) ? $item->{PostfixCommentLength} + $pads->CommentLen : 0)
        + (($includeTrailingComma) ? $pads->CommaLen : 0);
    if ($item->{Complexity} > $self->{Options}->{MaxInlineComplexity} || $lengthToConsider > $self->_AvailableLineSpace($depth)) {
        return 0;
    }
    $self->{_buffer}->Add($self->{Options}->{PrefixString}, $pads->Indent($depth));
    $self->_InlineElement($item, $includeTrailingComma, $parentTemplate);
    $self->{_buffer}->EndLine($pads->EOL);
    return 1;
}

sub _FormatContainerCompactMultiline {
    my ($self, $item, $depth, $includeTrailingComma, $template, $parentTemplate) = @_;
    return 0 if $item->{Type} != Array;
    return 0 if scalar(@{ $item->{Children} }) == 0 || scalar(@{ $item->{Children} }) < $self->{Options}->{MinCompactArrayRowItems};
    return 0 if $item->{Complexity} > $self->{Options}->{MaxCompactArrayComplexity};
    return 0 if $item->{RequiresMultipleLines};
    my $useTableFormatting = ($template->{Type} != TC_Unknown && $template->{Type} != TC_Mixed);
    my $likelyAvailableLineSpace = $self->_AvailableLineSpace($depth + 1);
    my $avgItemWidth = $self->{_pads}->CommaLen;
    if ($useTableFormatting) {
        $avgItemWidth += $template->{TotalLength};
    } else {
        my $sum = 0; $sum += $_->{MinimumTotalLength} for @{ $item->{Children} };
        $avgItemWidth += $sum / scalar(@{ $item->{Children} });
    }
    return 0 if $avgItemWidth * $self->{Options}->{MinCompactArrayRowItems} > $likelyAvailableLineSpace;

    my $depthAfterColon = $self->_StandardFormatStart($item, $depth, $parentTemplate);
    $self->{_buffer}->Add($self->{_pads}->Start($item->{Type}, Empty));
    my $availableLineSpace = $self->_AvailableLineSpace($depthAfterColon + 1);
    my $remainingLineSpace = -1;
    for (my $i=0; $i<@{ $item->{Children} }; ++$i) {
        my $child = $item->{Children}->[$i];
        my $needsComma = ($i < @{ $item->{Children} } - 1);
        my $spaceNeededForNext = ($needsComma ? $self->{_pads}->CommaLen : 0)
            + ($useTableFormatting ? $template->{TotalLength} : $child->{MinimumTotalLength});
        if ($remainingLineSpace < $spaceNeededForNext) {
            $self->{_buffer}->EndLine($self->{_pads}->EOL)->Add($self->{Options}->{PrefixString}, $self->{_pads}->Indent($depthAfterColon+1));
            $remainingLineSpace = $availableLineSpace;
        }
        if ($useTableFormatting) {
            $self->_InlineTableRowSegment($template, $child, $needsComma, 0);
        } else {
            $self->_InlineElement($child, $needsComma, undef);
        }
        $remainingLineSpace -= $spaceNeededForNext;
    }
    $self->{_buffer}->EndLine($self->{_pads}->EOL)->Add($self->{Options}->{PrefixString}, $self->{_pads}->Indent($depthAfterColon),
        $self->{_pads}->End($item->{Type}, Empty));
    $self->_StandardFormatEnd($item, $includeTrailingComma);
    return 1;
}

sub _FormatContainerTable {
    my ($self, $item, $depth, $includeTrailingComma, $template, $parentTemplate) = @_;
    return 0 if $item->{Complexity} > $self->{Options}->{MaxTableRowComplexity} + 1;
    return 0 if $template->{RequiresMultipleLines};
    my $availableSpaceDepth = ($item->{MiddleCommentHasNewLine}) ? $depth + 2 : $depth + 1;
    my $availableSpace = $self->_AvailableLineSpace($availableSpaceDepth) - $self->{_pads}->CommaLen;
    foreach my $ch (@{ $item->{Children} }) {
        next if _IsCommentOrBlankLine($ch->{Type});
        return 0 if $ch->{MinimumTotalLength} > $availableSpace;
    }
    if ($template->{Type} == TC_Mixed || !$template->TryToFit($availableSpace)) {
        return 0;
    }
    my $depthAfterColon = $self->_StandardFormatStart($item, $depth, $parentTemplate);
    $self->{_buffer}->Add($self->{_pads}->Start($item->{Type}, Empty))->EndLine($self->{_pads}->EOL);
    my $lastElementIndex = _IndexOfLastElement($item->{Children});
    for (my $i=0; $i<@{ $item->{Children} }; ++$i) {
        my $rowItem = $item->{Children}->[$i];
        if ($rowItem->{Type} == BlankLine) {
            $self->_FormatBlankLine();
            next;
        }
        if ($rowItem->{Type} == LineComment || $rowItem->{Type} == BlockComment) {
            $self->_FormatStandaloneComment($rowItem, $depthAfterColon+1);
            next;
        }
        $self->{_buffer}->Add($self->{Options}->{PrefixString}, $self->{_pads}->Indent($depthAfterColon+1));
        $self->_InlineTableRowSegment($template, $rowItem, ($i<$lastElementIndex), 1);
        $self->{_buffer}->EndLine($self->{_pads}->EOL);
    }
    $self->{_buffer}->Add($self->{Options}->{PrefixString}, $self->{_pads}->Indent($depthAfterColon),
        $self->{_pads}->End($item->{Type}, Empty));
    $self->_StandardFormatEnd($item, $includeTrailingComma);
    return 1;
}

sub _FormatContainerExpanded {
    my ($self, $item, $depth, $includeTrailingComma, $template, $parentTemplate) = @_;
    my $depthAfterColon = $self->_StandardFormatStart($item, $depth, $parentTemplate);
    $self->{_buffer}->Add($self->{_pads}->Start($item->{Type}, Empty))->EndLine($self->{_pads}->EOL);
    my $alignProps = ($item->{Type} == Object)
        && ($template->{NameLength} - $template->{NameMinimum} <= $self->{Options}->{MaxPropNamePadding})
        && (!$template->{AnyMiddleCommentHasNewline})
        && ($self->_AvailableLineSpace($depth + 1) >= $template->AtomicItemSize());
    my $templateToPass = $alignProps ? $template : undef;
    my $lastElementIndex = _IndexOfLastElement($item->{Children});
    for (my $i=0; $i<@{ $item->{Children} }; ++$i) {
        $self->_FormatItem($item->{Children}->[$i], $depthAfterColon+1, ($i<$lastElementIndex), $templateToPass);
    }
    $self->{_buffer}->Add($self->{Options}->{PrefixString}, $self->{_pads}->Indent($depthAfterColon),
        $self->{_pads}->End($item->{Type}, Empty));
    $self->_StandardFormatEnd($item, $includeTrailingComma);
}

sub _FormatStandaloneComment {
    my ($self, $item, $depth) = @_;
    my @commentRows = _NormalizeMultilineComment($item->{Value}, $item->{InputPosition}->{Column});
    foreach my $line (@commentRows) {
        $self->{_buffer}->Add($self->{Options}->{PrefixString}, $self->{_pads}->Indent($depth), $line)->EndLine($self->{_pads}->EOL);
    }
}

sub _FormatBlankLine {
    my ($self) = @_;
    $self->{_buffer}->Add($self->{Options}->{PrefixString})->EndLine($self->{_pads}->EOL);
}

sub _FormatInlineElement {
    my ($self, $item, $depth, $includeTrailingComma, $parentTemplate) = @_;
    $self->{_buffer}->Add($self->{Options}->{PrefixString}, $self->{_pads}->Indent($depth));
    $self->_InlineElement($item, $includeTrailingComma, $parentTemplate);
    $self->{_buffer}->EndLine($self->{_pads}->EOL);
}

sub _FormatSplitKeyValue {
    my ($self, $item, $depth, $includeTrailingComma, $parentTemplate) = @_;
    $self->_StandardFormatStart($item, $depth, $parentTemplate);
    $self->{_buffer}->Add($item->{Value});
    $self->_StandardFormatEnd($item, $includeTrailingComma);
}

sub _StandardFormatStart {
    my ($self, $item, $depth, $parentTemplate) = @_;
    my $pads = $self->{_pads};
    $self->{_buffer}->Add($self->{Options}->{PrefixString}, $pads->Indent($depth));
    if ($parentTemplate) {
        $self->_AddToBufferFixed($item->{PrefixComment}, $item->{PrefixCommentLength}, $parentTemplate->{PrefixCommentLength}, $pads->Comment, 0);
        $self->_AddToBufferFixed($item->{Name}, $item->{NameLength}, $parentTemplate->{NameLength}, $pads->Colon, $self->{Options}->{ColonBeforePropNamePadding});
    } else {
        $self->_AddToBuffer($item->{PrefixComment}, $item->{PrefixCommentLength}, $pads->Comment);
        $self->_AddToBuffer($item->{Name}, $item->{NameLength}, $pads->Colon);
    }
    if ($item->{MiddleCommentLength} == 0) {
        return $depth;
    }
    if (!$item->{MiddleCommentHasNewLine}) {
        my $middlePad = ($parentTemplate) ? ($parentTemplate->{MiddleCommentLength} - $item->{MiddleCommentLength}) : 0;
        $self->{_buffer}->Add($item->{MiddleComment})->Spaces($middlePad)->Add($pads->Comment);
        return $depth;
    }
    my @commentRows = _NormalizeMultilineComment($item->{MiddleComment}, 9**9);
    $self->{_buffer}->EndLine($pads->EOL);
    foreach my $row (@commentRows) {
        $self->{_buffer}->Add($self->{Options}->{PrefixString}, $pads->Indent($depth+1), $row)->EndLine($pads->EOL);
    }
    $self->{_buffer}->Add($self->{Options}->{PrefixString}, $pads->Indent($depth+1));
    return $depth + 1;
}

sub _StandardFormatEnd {
    my ($self, $item, $includeTrailingComma) = @_;
    if ($includeTrailingComma && $item->{IsPostCommentLineStyle}) {
        $self->{_buffer}->Add($self->{_pads}->Comma);
    }
    if ($item->{PostfixCommentLength} > 0) {
        $self->{_buffer}->Add($self->{_pads}->Comment, $item->{PostfixComment});
    }
    if ($includeTrailingComma && !$item->{IsPostCommentLineStyle}) {
        $self->{_buffer}->Add($self->{_pads}->Comma);
    }
    $self->{_buffer}->EndLine($self->{_pads}->EOL);
}

sub _InlineElement {
    my ($self, $item, $includeTrailingComma, $parentTemplate) = @_;
    my $pads = $self->{_pads};
    die FracturedJson::Error->new('Logic error - trying to inline invalid element') if $item->{RequiresMultipleLines};
    if ($parentTemplate) {
        $self->_AddToBufferFixed($item->{PrefixComment}, $item->{PrefixCommentLength}, $parentTemplate->{PrefixCommentLength}, $pads->Comment, 0);
        $self->_AddToBufferFixed($item->{Name}, $item->{NameLength}, $parentTemplate->{NameLength}, $pads->Colon, $self->{Options}->{ColonBeforePropNamePadding});
        $self->_AddToBufferFixed($item->{MiddleComment}, $item->{MiddleCommentLength}, $parentTemplate->{MiddleCommentLength}, $pads->Comment, 0);
    } else {
        $self->_AddToBuffer($item->{PrefixComment}, $item->{PrefixCommentLength}, $pads->Comment);
        $self->_AddToBuffer($item->{Name}, $item->{NameLength}, $pads->Colon);
        $self->_AddToBuffer($item->{MiddleComment}, $item->{MiddleCommentLength}, $pads->Comment);
    }
    $self->_InlineElementRaw($item);
    if ($includeTrailingComma && $item->{IsPostCommentLineStyle}) {
        $self->{_buffer}->Add($pads->Comma);
    }
    if ($item->{PostfixCommentLength} > 0) {
        $self->{_buffer}->Add($pads->Comment, $item->{PostfixComment});
    }
    if ($includeTrailingComma && !$item->{IsPostCommentLineStyle}) {
        $self->{_buffer}->Add($pads->Comma);
    }
}

sub _InlineElementRaw {
    my ($self, $item) = @_;
    my $pads = $self->{_pads};
    if ($item->{Type} == Array) {
        my $padType = _GetPaddingType($item);
        $self->{_buffer}->Add($pads->ArrStart($padType));
        for (my $i=0; $i<@{ $item->{Children} }; ++$i) {
            $self->_InlineElement($item->{Children}->[$i], ($i<@{ $item->{Children} }-1), undef);
        }
        $self->{_buffer}->Add($pads->ArrEnd($padType));
    }
    elsif ($item->{Type} == Object) {
        my $padType = _GetPaddingType($item);
        $self->{_buffer}->Add($pads->ObjStart($padType));
        for (my $i=0; $i<@{ $item->{Children} }; ++$i) {
            $self->_InlineElement($item->{Children}->[$i], ($i<@{ $item->{Children} }-1), undef);
        }
        $self->{_buffer}->Add($pads->ObjEnd($padType));
    }
    else {
        $self->{_buffer}->Add($item->{Value});
    }
}

sub _InlineTableRowSegment {
    my ($self, $template, $item, $includeTrailingComma, $isWholeRow) = @_;
    my $pads = $self->{_pads};
    $self->_AddToBufferFixed($item->{PrefixComment}, $item->{PrefixCommentLength}, $template->{PrefixCommentLength}, $pads->Comment, 0);
    $self->_AddToBufferFixed($item->{Name}, $item->{NameLength}, $template->{NameLength}, $pads->Colon, $self->{Options}->{ColonBeforePropNamePadding});
    $self->_AddToBufferFixed($item->{MiddleComment}, $item->{MiddleCommentLength}, $template->{MiddleCommentLength}, $pads->Comment, 0);
    my $commaBeforePad = ($self->{Options}->{TableCommaPlacement} == BeforePadding)
        || ($self->{Options}->{TableCommaPlacement} == BeforePaddingExceptNumbers && ($template->{Type} != TC_Number));
    my $commaPos;
    if ($template->{PostfixCommentLength} > 0 && !$template->{IsAnyPostCommentLineStyle}) {
        if ($item->{PostfixCommentLength} > 0) {
            $commaPos = ($commaBeforePad) ? 'BeforeCommentPadding' : 'AfterCommentPadding';
        }
        else {
            $commaPos = ($commaBeforePad) ? 'BeforeValuePadding' : 'AfterCommentPadding';
        }
    }
    else {
        $commaPos = ($commaBeforePad) ? 'BeforeValuePadding' : 'AfterValuePadding';
    }
    my $commaType = ($includeTrailingComma) ? $pads->Comma : ($isWholeRow ? $pads->DummyComma : '');
    if (@{ $template->{Children} } > 0 && $item->{Type} != Null) {
        if ($template->{Type} == Array) {
            $self->_InlineTableRawArray($template, $item);
        }
        else {
            $self->_InlineTableRawObject($template, $item);
        }
        if ($commaPos eq 'BeforeValuePadding') {
            $self->{_buffer}->Add($commaType);
        }
        if ($template->{ShorterThanNullAdjustment} > 0) {
            $self->{_buffer}->Spaces($template->{ShorterThanNullAdjustment});
        }
    }
    elsif ($template->{Type} == TC_Number) {
        my $numberCommaType = ($commaPos eq 'BeforeValuePadding') ? $commaType : '';
        $template->FormatNumber($self->{_buffer}, $item, $numberCommaType);
    }
    else {
        $self->_InlineElementRaw($item);
        if ($commaPos eq 'BeforeValuePadding') {
            $self->{_buffer}->Add($commaType);
        }
        $self->{_buffer}->Spaces($template->{CompositeValueLength} - $item->{ValueLength});
    }
    if ($commaPos eq 'AfterValuePadding') {
        $self->{_buffer}->Add($commaType);
    }
    if ($template->{PostfixCommentLength} > 0) {
        $self->{_buffer}->Add($pads->Comment, $item->{PostfixComment});
    }
    if ($commaPos eq 'BeforeCommentPadding') {
        $self->{_buffer}->Add($commaType);
    }
    $self->{_buffer}->Spaces($template->{PostfixCommentLength} - $item->{PostfixCommentLength});
    if ($commaPos eq 'AfterCommentPadding') {
        $self->{_buffer}->Add($commaType);
    }
}

sub _InlineTableRawArray {
    my ($self, $template, $item) = @_;
    $self->{_buffer}->Add($self->{_pads}->ArrStart($template->{PadType}));
    for (my $i=0; $i<@{ $template->{Children} }; ++$i) {
        my $isLastInTemplate = ($i == @{ $template->{Children} } - 1);
        my $isLastInArray = ($i == @{ $item->{Children} } - 1);
        my $isPastEndOfArray = ($i >= @{ $item->{Children} });
        my $subTemplate = $template->{Children}->[$i];
        if ($isPastEndOfArray) {
            $self->{_buffer}->Spaces($subTemplate->{TotalLength});
            if (!$isLastInTemplate) {
                $self->{_buffer}->Add($self->{_pads}->DummyComma);
            }
        }
        else {
            $self->_InlineTableRowSegment($subTemplate, $item->{Children}->[$i], !$isLastInArray, 0);
            if ($isLastInArray && !$isLastInTemplate) {
                $self->{_buffer}->Add($self->{_pads}->DummyComma);
            }
        }
    }
    $self->{_buffer}->Add($self->{_pads}->ArrEnd($template->{PadType}));
}

sub _InlineTableRawObject {
    my ($self, $template, $item) = @_;
    my @matches = map {
        my $sub = $_;
        my ($ji) = grep {
            defined $_->{Name} && defined $sub->{LocationInParent} && $_->{Name} eq $sub->{LocationInParent}
        } @{ $item->{Children} };
        { tt=>$sub, ji=>$ji }
    } @{ $template->{Children} };
    my $lastNonNullIdx = scalar(@matches) - 1;
    while ($lastNonNullIdx >= 0 && !$matches[$lastNonNullIdx]->{ji}) {
        $lastNonNullIdx -= 1;
    }
    $self->{_buffer}->Add($self->{_pads}->ObjStart($template->{PadType}));
    for (my $i=0; $i<@matches; ++$i) {
        my $subTemplate = $matches[$i]->{tt};
        my $subItem = $matches[$i]->{ji};
        my $isLastInObject = ($i == $lastNonNullIdx);
        my $isLastInTemplate = ($i == @matches - 1);
        if ($subItem) {
            $self->_InlineTableRowSegment($subTemplate, $subItem, !$isLastInObject, 0);
            if ($isLastInObject && !$isLastInTemplate) {
                $self->{_buffer}->Add($self->{_pads}->DummyComma);
            }
        }
        else {
            $self->{_buffer}->Spaces($subTemplate->{TotalLength});
            if (!$isLastInTemplate) {
                $self->{_buffer}->Add($self->{_pads}->DummyComma);
            }
        }
    }
    $self->{_buffer}->Add($self->{_pads}->ObjEnd($template->{PadType}));
}

sub _AvailableLineSpace {
    my ($self, $depth) = @_;
    return $self->{Options}->{MaxTotalLineLength} - $self->{_pads}->PrefixStringLen - $self->{Options}->{IndentSpaces} * $depth;
}

sub _MinifyItem {
    my ($self, $item, $atStartOfNewLine) = @_;
    my $newline = "\n";
    $self->{_buffer}->Add($item->{PrefixComment});
    if (length($item->{Name})>0) {
        $self->{_buffer}->Add($item->{Name}, ':');
    }
    if (index($item->{MiddleComment}, $newline) >= 0) {
        my @normalized = _NormalizeMultilineComment($item->{MiddleComment}, 9**9);
        $self->{_buffer}->Add($_, $newline) for @normalized;
    }
    else {
        $self->{_buffer}->Add($item->{MiddleComment});
    }
    if ($item->{Type} == Array || $item->{Type} == Object) {
        my $closeBracket;
        if ($item->{Type} == Array) {
            $self->{_buffer}->Add('[');
            $closeBracket = ']';
        }
        else {
            $self->{_buffer}->Add('{');
            $closeBracket = '}';
        }
        my $needsComma = 0;
        my $atNew = 0;
        foreach my $child (@{ $item->{Children} }) {
            if (!_IsCommentOrBlankLine($child->{Type})) {
                $self->{_buffer}->Add(',') if $needsComma;
                $needsComma = 1;
            }
            $atNew = $self->_MinifyItem($child, $atNew);
        }
        $self->{_buffer}->Add($closeBracket);
    }
    elsif ($item->{Type} == BlankLine) {
        if (!$atStartOfNewLine) {
            $self->{_buffer}->Add($newline);
        }
        $self->{_buffer}->Add($newline);
        return 1;
    }
    elsif ($item->{Type} == LineComment) {
        if (!$atStartOfNewLine) {
            $self->{_buffer}->Add($newline);
        }
        $self->{_buffer}->Add($item->{Value}, $newline);
        return 1;
    }
    elsif ($item->{Type} == BlockComment) {
        if (!$atStartOfNewLine) {
            $self->{_buffer}->Add($newline);
        }
        if (index($item->{Value}, $newline) >= 0) {
            my @normalized = _NormalizeMultilineComment($item->{Value}, $item->{InputPosition}->{Column});
            $self->{_buffer}->Add($_, $newline) for @normalized;
            return 1;
        }
        $self->{_buffer}->Add($item->{Value}, $newline);
        return 1;
    }
    else {
        $self->{_buffer}->Add($item->{Value});
    }
    $self->{_buffer}->Add($item->{PostfixComment});
    if (length($item->{PostfixComment})>0 && $item->{IsPostCommentLineStyle}) {
        $self->{_buffer}->Add($newline);
        return 1;
    }
    return 0;
}

sub _AddToBuffer {
    my ($self, $value, $valueWidth, $separator) = @_;
    return if $valueWidth <= 0;
    $self->{_buffer}->Add($value, $separator);
}

sub _AddToBufferFixed {
    my ($self, $value, $valueWidth, $fieldWidth, $separator, $separatorBeforePadding) = @_;
    return if $fieldWidth <= 0;
    my $padWidth = $fieldWidth - $valueWidth;
    if ($separatorBeforePadding) {
        $self->{_buffer}->Add($value, $separator)->Spaces($padWidth);
    } else {
        $self->{_buffer}->Add($value)->Spaces($padWidth)->Add($separator);
    }
}

sub _GetPaddingType {
    my ($arrOrObj) = @_;
    return Empty if @{ $arrOrObj->{Children} } == 0;
    return ($arrOrObj->{Complexity} >= 2) ? Complex : Simple;
}

sub _NormalizeMultilineComment {
    my ($comment, $firstLineColumn) = @_;
    my $normalized = $comment;
    $normalized =~ s/\r//g;
    my @commentRows = grep { length($_)>0 } split(/\n/, $normalized);
    for (my $i=1; $i<@commentRows; ++$i) {
        my $line = $commentRows[$i];
        my $nonWsIdx = 0;
        while ($nonWsIdx < length($line) && $nonWsIdx < $firstLineColumn && substr($line,$nonWsIdx,1) =~ /\s/) {
            $nonWsIdx += 1;
        }
        $commentRows[$i] = substr($line, $nonWsIdx);
    }
    return @commentRows;
}

sub _IndexOfLastElement {
    my ($itemList) = @_;
    for (my $i=$#$itemList; $i>=0; --$i) {
        return $i if !_IsCommentOrBlankLine($itemList->[$i]->{Type});
    }
    return -1;
}

sub _IsCommentOrBlankLine {
    my ($type) = @_;
    return ($type == BlankLine || $type == BlockComment || $type == LineComment);
}

1;
