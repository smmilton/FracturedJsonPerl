package FracturedJson::Parser;
use strict;
use warnings;
use FracturedJson::Options;
use FracturedJson::TokenEnumerator;
use FracturedJson::JsonItem qw(new_item);
use FracturedJson::JsonItemType qw(Null False True String Number Object Array BlankLine LineComment BlockComment);
use FracturedJson::TokenType (); # avoid name collisions, use qualified lookups
use FracturedJson::Error;
use FracturedJson::InputPosition qw(clone_pos);
use FracturedJson::CommentPolicy qw(TreatAsError Preserve Remove);
use FracturedJson::TokenGenerator qw(TokenGenerator);

use constant {
    T_BeginArray   => FracturedJson::TokenType::BeginArray(),
    T_EndArray     => FracturedJson::TokenType::EndArray(),
    T_BeginObject  => FracturedJson::TokenType::BeginObject(),
    T_EndObject    => FracturedJson::TokenType::EndObject(),
    T_String       => FracturedJson::TokenType::String(),
    T_Number       => FracturedJson::TokenType::Number(),
    T_Null         => FracturedJson::TokenType::Null(),
    T_True         => FracturedJson::TokenType::True(),
    T_False        => FracturedJson::TokenType::False(),
    T_BlockComment => FracturedJson::TokenType::BlockComment(),
    T_LineComment  => FracturedJson::TokenType::LineComment(),
    T_BlankLine    => FracturedJson::TokenType::BlankLine(),
    T_Comma        => FracturedJson::TokenType::Comma(),
    T_Colon        => FracturedJson::TokenType::Colon(),
};

sub new {
    my ($class) = @_;
    my $self = {
        Options => FracturedJson::Options->new(),
    };
    bless $self, $class;
    return $self;
}

sub ParseTopLevel {
    my ($self, $input_json, $stopAfterFirstElem) = @_;
    my $tokens = TokenGenerator($input_json // '');
    my $enumerator = FracturedJson::TokenEnumerator->new($tokens);
    return $self->_ParseTopLevelFromEnum($enumerator, $stopAfterFirstElem);
}

sub _ParseTopLevelFromEnum {
    my ($self, $enumerator, $stopAfterFirstElem) = @_;
    my @topLevelItems;
    my $topLevelElemSeen = 0;
    while (1) {
        if (!$enumerator->MoveNext) {
            return \@topLevelItems;
        }
        my $item = $self->_ParseItem($enumerator);
        my $isComment = ($item->{Type} == BlockComment || $item->{Type} == LineComment);
        my $isBlank = ($item->{Type} == BlankLine);
        if ($isBlank) {
            push @topLevelItems, $item if $self->{Options}->{PreserveBlankLines};
        }
        elsif ($isComment) {
            if ($self->{Options}->{CommentPolicy} == TreatAsError) {
                die FracturedJson::Error->new('Comments not allowed with current options', $item->{InputPosition});
            }
            if ($self->{Options}->{CommentPolicy} == Preserve) {
                push @topLevelItems, $item;
            }
        }
        else {
            if ($stopAfterFirstElem && $topLevelElemSeen) {
                die FracturedJson::Error->new('Unexpected start of second top level element', $item->{InputPosition});
            }
            push @topLevelItems, $item;
            $topLevelElemSeen = 1;
        }
    }
}

sub _ParseItem {
    my ($self, $enumerator) = @_;
    my $t = $enumerator->Current->{Type};
    if ($t == T_BeginArray) {
        return $self->_ParseArray($enumerator);
    }
    elsif ($t == T_BeginObject) {
        return $self->_ParseObject($enumerator);
    }
    else {
        return $self->_ParseSimple($enumerator->Current);
    }
}

sub _ParseSimple {
    my ($self, $token) = @_;
    my $item = new_item();
    $item->{Type} = _ItemTypeFromTokenType($token);
    $item->{Value} = $token->{Text};
    $item->{InputPosition} = clone_pos($token->{InputPosition});
    $item->{Complexity} = 0;
    return $item;
}

sub _ParseArray {
    my ($self, $enumerator) = @_;
    die FracturedJson::Error->new('Parser logic error', $enumerator->Current->{InputPosition})
        if $enumerator->Current->{Type} != T_BeginArray;
    my $starting_pos = clone_pos($enumerator->Current->{InputPosition});
    my $elemNeedingPostComment;
    my $elemNeedingPostEndRow = -1;
    my $unplacedComment;
    my @childList;
    my $commaStatus = 'EmptyCollection';
    my $endOfArrayFound = 0;
    my $thisArrayComplexity = 0;

    while (!$endOfArrayFound) {
        my $token = _GetNextTokenOrThrow($enumerator, $starting_pos);
        my $needsHome = $unplacedComment
            && ($unplacedComment->{InputPosition}->{Row} != $token->{InputPosition}->{Row}
                || $token->{Type} == T_EndArray);
        if ($needsHome) {
            if ($elemNeedingPostComment) {
                $elemNeedingPostComment->{PostfixComment} = $unplacedComment->{Value};
                $elemNeedingPostComment->{IsPostCommentLineStyle} = ($unplacedComment->{Type} == LineComment);
            }
            else {
                push @childList, $unplacedComment;
            }
            $unplacedComment = undef;
        }
        if ($elemNeedingPostComment && $elemNeedingPostEndRow != $token->{InputPosition}->{Row}) {
            $elemNeedingPostComment = undef;
        }

        if ($token->{Type} == T_EndArray) {
            if ($commaStatus eq 'CommaSeen' && !$self->{Options}->{AllowTrailingCommas}) {
                die FracturedJson::Error->new('Array may not end with a comma with current options', $token->{InputPosition});
            }
            $endOfArrayFound = 1;
        }
        elsif ($token->{Type} == T_Comma) {
            if ($commaStatus ne 'ElementSeen') {
                die FracturedJson::Error->new('Unexpected comma in array', $token->{InputPosition});
            }
            $commaStatus = 'CommaSeen';
        }
        elsif ($token->{Type} == T_BlankLine) {
            if ($self->{Options}->{PreserveBlankLines}) {
                push @childList, $self->_ParseSimple($token);
            }
        }
        elsif ($token->{Type} == T_BlockComment) {
            if ($self->{Options}->{CommentPolicy} == Remove) {
                next;
            }
            if ($self->{Options}->{CommentPolicy} == TreatAsError) {
                die FracturedJson::Error->new('Comments not allowed with current options', $token->{InputPosition});
            }
            if ($unplacedComment) {
                push @childList, $unplacedComment;
                $unplacedComment = undef;
            }
            my $commentItem = $self->_ParseSimple($token);
            if (_IsMultilineComment($commentItem)) {
                push @childList, $commentItem;
                next;
            }
            if ($elemNeedingPostComment && $commaStatus eq 'ElementSeen') {
                $elemNeedingPostComment->{PostfixComment} = $commentItem->{Value};
                $elemNeedingPostComment->{IsPostCommentLineStyle} = 0;
                $elemNeedingPostComment = undef;
                next;
            }
            $unplacedComment = $commentItem;
        }
        elsif ($token->{Type} == T_LineComment) {
            if ($self->{Options}->{CommentPolicy} == Remove) {
                next;
            }
            if ($self->{Options}->{CommentPolicy} == TreatAsError) {
                die FracturedJson::Error->new('Comments not allowed with current options', $token->{InputPosition});
            }
            if ($unplacedComment) {
                push @childList, $unplacedComment;
                push @childList, $self->_ParseSimple($token);
                $unplacedComment = undef;
                next;
            }
            if ($elemNeedingPostComment) {
                $elemNeedingPostComment->{PostfixComment} = $token->{Text};
                $elemNeedingPostComment->{IsPostCommentLineStyle} = 1;
                $elemNeedingPostComment = undef;
                next;
            }
            $unplacedComment = $self->_ParseSimple($token);
        }
        elsif ($token->{Type} == T_False || $token->{Type} == T_True || $token->{Type} == T_Null
            || $token->{Type} == T_String || $token->{Type} == T_Number || $token->{Type} == T_BeginArray
            || $token->{Type} == T_BeginObject) {
            if ($commaStatus eq 'ElementSeen') {
                die FracturedJson::Error->new('Comma missing while processing array', $token->{InputPosition});
            }
            my $element = $self->_ParseItem($enumerator);
            $commaStatus = 'ElementSeen';
            $thisArrayComplexity = ($thisArrayComplexity > $element->{Complexity}+1) ? $thisArrayComplexity : ($element->{Complexity}+1);
            if ($unplacedComment) {
                $element->{PrefixComment} = $unplacedComment->{Value};
                $unplacedComment = undef;
            }
            push @childList, $element;
            $elemNeedingPostComment = $element;
            $elemNeedingPostEndRow = $enumerator->Current->{InputPosition}->{Row};
        }
        else {
            die FracturedJson::Error->new('Unexpected token in array', $token->{InputPosition});
        }
    }

    my $arrayItem = new_item(Array);
    $arrayItem->{InputPosition} = $starting_pos;
    $arrayItem->{Complexity} = $thisArrayComplexity;
    $arrayItem->{Children} = \@childList;
    return $arrayItem;
}

sub _ParseObject {
    my ($self, $enumerator) = @_;
    die FracturedJson::Error->new('Parser logic error', $enumerator->Current->{InputPosition})
        if $enumerator->Current->{Type} != T_BeginObject;
    my $starting_pos = clone_pos($enumerator->Current->{InputPosition});
    my @childList;
    my ($propertyName, $propertyValue);
    my $linePropValueEnds = -1;
    my @beforePropComments;
    my @midPropComments;
    my $afterPropComment;
    my $afterPropCommentWasAfterComma = 0;
    my $phase = 'BeforePropName';
    my $thisObjComplexity = 0;
    my $endOfObject = 0;

    while (!$endOfObject) {
        my $token = _GetNextTokenOrThrow($enumerator, $starting_pos);
        my $isNewLine = ($linePropValueEnds != $token->{InputPosition}->{Row});
        my $isEndOfObject = ($token->{Type} == T_EndObject);
        my $startingNextPropName = ($token->{Type} == T_String && $phase eq 'AfterComma');
        my $isExcessPostComment = $afterPropComment && ($token->{Type} == T_BlockComment || $token->{Type} == T_LineComment);
        my $needToFlush = $propertyName && $propertyValue && ($isNewLine || $isEndOfObject || $startingNextPropName || $isExcessPostComment);
        if ($needToFlush) {
            my $commentToHoldForNextElem;
            if ($startingNextPropName && $afterPropCommentWasAfterComma && !$isNewLine) {
                $commentToHoldForNextElem = $afterPropComment;
                $afterPropComment = undef;
            }
            _AttachObjectValuePieces(\@childList, $propertyName, $propertyValue, $linePropValueEnds,
                \@beforePropComments, \@midPropComments, $afterPropComment);
            $thisObjComplexity = ($thisObjComplexity > $propertyValue->{Complexity}+1) ? $thisObjComplexity : ($propertyValue->{Complexity}+1);
            $propertyName = undef;
            $propertyValue = undef;
            @beforePropComments = ();
            @midPropComments = ();
            $afterPropComment = undef;
            if ($commentToHoldForNextElem) {
                push @beforePropComments, $commentToHoldForNextElem;
            }
        }

        if ($token->{Type} == T_BlankLine) {
            next if !$self->{Options}->{PreserveBlankLines};
            next if ($phase eq 'AfterPropName' || $phase eq 'AfterColon');
            push @childList, @beforePropComments;
            @beforePropComments = ();
            push @childList, $self->_ParseSimple($token);
        }
        elsif ($token->{Type} == T_BlockComment || $token->{Type} == T_LineComment) {
            if ($self->{Options}->{CommentPolicy} == Remove) {
                next;
            }
            if ($self->{Options}->{CommentPolicy} == TreatAsError) {
                die FracturedJson::Error->new('Comments not allowed with current options', $token->{InputPosition});
            }
            if ($phase eq 'BeforePropName' || !$propertyName) {
                push @beforePropComments, $self->_ParseSimple($token);
            }
            elsif ($phase eq 'AfterPropName' || $phase eq 'AfterColon') {
                push @midPropComments, $token;
            }
            else {
                $afterPropComment = $self->_ParseSimple($token);
                $afterPropCommentWasAfterComma = ($phase eq 'AfterComma');
            }
        }
        elsif ($token->{Type} == T_EndObject) {
            if ($phase eq 'AfterPropName' || $phase eq 'AfterColon') {
                die FracturedJson::Error->new('Unexpected end of object', $token->{InputPosition});
            }
            $endOfObject = 1;
        }
        elsif ($token->{Type} == T_String) {
            if ($phase eq 'BeforePropName' || $phase eq 'AfterComma') {
                $propertyName = $token;
                $phase = 'AfterPropName';
            }
            elsif ($phase eq 'AfterColon') {
                $propertyValue = $self->_ParseItem($enumerator);
                $linePropValueEnds = $enumerator->Current->{InputPosition}->{Row};
                $phase = 'AfterPropValue';
            }
            else {
                die FracturedJson::Error->new('Unexpected string found while processing object', $token->{InputPosition});
            }
        }
        elsif ($token->{Type} == T_False || $token->{Type} == T_True || $token->{Type} == T_Null || $token->{Type} == T_Number
            || $token->{Type} == T_BeginArray || $token->{Type} == T_BeginObject) {
            if ($phase ne 'AfterColon') {
                die FracturedJson::Error->new('Unexpected element while processing object', $token->{InputPosition});
            }
            $propertyValue = $self->_ParseItem($enumerator);
            $linePropValueEnds = $enumerator->Current->{InputPosition}->{Row};
            $phase = 'AfterPropValue';
        }
        elsif ($token->{Type} == T_Colon) {
            if ($phase ne 'AfterPropName') {
                die FracturedJson::Error->new('Unexpected colon while processing object', $token->{InputPosition});
            }
            $phase = 'AfterColon';
        }
        elsif ($token->{Type} == T_Comma) {
            if ($phase ne 'AfterPropValue') {
                die FracturedJson::Error->new('Unexpected comma while processing object', $token->{InputPosition});
            }
            $phase = 'AfterComma';
        }
        else {
            die FracturedJson::Error->new('Unexpected token while processing object', $token->{InputPosition});
        }
    }

    if (!$self->{Options}->{AllowTrailingCommas} && $phase eq 'AfterComma') {
        die FracturedJson::Error->new('Object may not end with comma with current options', $enumerator->Current->{InputPosition});
    }

    my $objItem = new_item(Object);
    $objItem->{InputPosition} = $starting_pos;
    $objItem->{Complexity} = $thisObjComplexity;
    $objItem->{Children} = \@childList;
    return $objItem;
}

sub _ItemTypeFromTokenType {
    my ($token) = @_;
    my $t = $token->{Type};
    return False if $t == T_False;
    return True if $t == T_True;
    return Null if $t == T_Null;
    return Number if $t == T_Number;
    return String if $t == T_String;
    return BlankLine if $t == T_BlankLine;
    return BlockComment if $t == T_BlockComment;
    return LineComment if $t == T_LineComment;
    die FracturedJson::Error->new('Unexpected Token', $token->{InputPosition});
}

sub _GetNextTokenOrThrow {
    my ($enumerator, $startPosition) = @_;
    if (!$enumerator->MoveNext) {
        die FracturedJson::Error->new('Unexpected end of input while processing array or object starting', $startPosition);
    }
    return $enumerator->Current;
}

sub _IsMultilineComment {
    my ($item) = @_;
    return ($item->{Type} == BlockComment) && (index($item->{Value}, "\n") >= 0);
}

sub _AttachObjectValuePieces {
    my ($objItemList, $nameToken, $element, $valueEndingLine, $beforeComments, $midComments, $afterComment) = @_;
    $element->{Name} = $nameToken->{Text};
    if (@$midComments > 0) {
        my $combined = '';
        for (my $i=0; $i<@$midComments; ++$i) {
            $combined .= $midComments->[$i]->{Text};
            if ($i < @$midComments-1 || $midComments->[$i]->{Type} == T_LineComment) {
                $combined .= "\n";
            }
        }
        $element->{MiddleComment} = $combined;
        $element->{MiddleCommentHasNewLine} = (index($combined, "\n") >= 0) ? 1 : 0;
    }
    if (@$beforeComments > 0) {
        my $last = pop @$beforeComments;
        if ($last->{Type} == BlockComment && $last->{InputPosition}->{Row} == $element->{InputPosition}->{Row}) {
            $element->{PrefixComment} = $last->{Value};
            push @$objItemList, @$beforeComments;
        }
        else {
            push @$objItemList, @$beforeComments;
            push @$objItemList, $last;
        }
    }
    push @$objItemList, $element;
    if ($afterComment) {
        if (!_IsMultilineComment($afterComment) && $afterComment->{InputPosition}->{Row} == $valueEndingLine) {
            $element->{PostfixComment} = $afterComment->{Value};
            $element->{IsPostCommentLineStyle} = ($afterComment->{Type} == LineComment);
        }
        else {
            push @$objItemList, $afterComment;
        }
    }
}

1;
