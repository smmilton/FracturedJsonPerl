package FracturedJson::TokenGenerator;
use strict;
use warnings;
use Exporter 'import';
use FracturedJson::ScannerState;
use FracturedJson::TokenType qw(BeginArray EndArray BeginObject EndObject String Number Null True False BlockComment LineComment BlankLine Comma Colon);
use Encode qw(decode FB_CROAK LEAVE_SRC);

our @EXPORT_OK = qw(TokenGenerator);

sub TokenGenerator {
    my ($input_json) = @_;
    $input_json = decode('UTF-8', $input_json // '', FB_CROAK | LEAVE_SRC);
    my $state = FracturedJson::ScannerState->new($input_json);
    my @tokens;

    while (1) {
        last if $state->AtEnd;
        my $ch = $state->Current;
        if (!defined $ch) { last; }

        if ($ch == _codeSpace() || $ch == _codeTab() || $ch == _codeCR()) {
            $state->Advance(1);
            next;
        }
        if ($ch == _codeLF()) {
            if (!$state->{NonWhitespaceSinceLastNewline}) {
                push @tokens, _ProcessSingleChar($state, "\n", BlankLine);
            }
            $state->NewLine();
            $state->SetTokenStart();
            next;
        }

        if    ($ch == _codeOpenCurly())  { push @tokens, _ProcessSingleChar($state, '{', BeginObject);  next; }
        elsif ($ch == _codeCloseCurly()) { push @tokens, _ProcessSingleChar($state, '}', EndObject);   next; }
        elsif ($ch == _codeOpenSquare()) { push @tokens, _ProcessSingleChar($state, '[', BeginArray);   next; }
        elsif ($ch == _codeCloseSquare()){ push @tokens, _ProcessSingleChar($state, ']', EndArray);     next; }
        elsif ($ch == _codeColon())      { push @tokens, _ProcessSingleChar($state, ':', Colon);        next; }
        elsif ($ch == _codeComma())      { push @tokens, _ProcessSingleChar($state, ',', Comma);        next; }
        elsif ($ch == _codeLittleT())    { push @tokens, _ProcessKeyword($state, 'true', True);        next; }
        elsif ($ch == _codeLittleF())    { push @tokens, _ProcessKeyword($state, 'false', False);      next; }
        elsif ($ch == _codeLittleN())    { push @tokens, _ProcessKeyword($state, 'null', Null);        next; }
        elsif ($ch == _codeSlash())      { push @tokens, _ProcessComment($state);                      next; }
        elsif ($ch == _codeQuote())      { push @tokens, _ProcessString($state);                       next; }
        elsif ($ch == _codeMinus())      { push @tokens, _ProcessNumber($state);                       next; }
        else {
            if (!_isDigit($ch)) {
                $state->Throw('Unexpected character');
            }
            push @tokens, _ProcessNumber($state);
            next;
        }
    }

    return \@tokens;
}

sub _ProcessSingleChar {
    my ($state, $symbol, $type) = @_;
    $state->SetTokenStart();
    my $token = $state->MakeToken($type, $symbol);
    $state->Advance(0);
    return $token;
}

sub _ProcessKeyword {
    my ($state, $keyword, $type) = @_;
    $state->SetTokenStart();
    for (my $i=1; $i<length($keyword); ++$i) {
        $state->Throw('Unexpected end of input while processing keyword') if $state->AtEnd;
        $state->Advance(0);
        if ($state->Current != ord(substr($keyword,$i,1))) {
            $state->Throw('Unexpected keyword');
        }
    }
    my $token = $state->MakeToken($type, $keyword);
    $state->Advance(0);
    return $token;
}

sub _ProcessComment {
    my ($state) = @_;
    $state->SetTokenStart();
    $state->Throw('Unexpected end of input while processing comment') if $state->AtEnd;
    $state->Advance(0);
    my $isBlock = 0;
    if ($state->Current == _codeStar()) {
        $isBlock = 1;
    }
    elsif ($state->Current != _codeSlash()) {
        $state->Throw('Bad character for start of comment');
    }

    $state->Advance(0);
    my $lastWasStar = 0;
    while (1) {
        if ($state->AtEnd) {
            if ($isBlock) {
                $state->Throw('Unexpected end of input while processing comment');
            }
            else {
                return $state->MakeTokenFromBuffer(LineComment, 1);
            }
        }

        my $ch = $state->Current;
        if ($ch == _codeLF()) {
            $state->NewLine();
            if (!$isBlock) {
                return $state->MakeTokenFromBuffer(LineComment, 1);
            }
            next;
        }

        $state->Advance(0);
        if ($ch == _codeSlash() && $lastWasStar) {
            return $state->MakeTokenFromBuffer(BlockComment, 0);
        }
        $lastWasStar = ($ch == _codeStar());
    }
}

sub _ProcessString {
    my ($state) = @_;
    $state->SetTokenStart();
    $state->Advance(0);
    my $lastEscape = 0;
    my $expectedHex = 0;
    while (1) {
        $state->Throw('Unexpected end of input while processing string') if $state->AtEnd;
        my $ch = $state->Current;
        if ($expectedHex > 0) {
            $state->Throw('Bad unicode escape in string') if !_isHex($ch);
            $expectedHex -= 1;
            $state->Advance(0);
            next;
        }
        if ($lastEscape) {
            $state->Throw('Bad escaped character in string') if !_isLegalAfterBackslash($ch);
            $expectedHex = 4 if ($ch == _codeLittleU());
            $lastEscape = 0;
            $state->Advance(0);
            next;
        }
        if (_isControl($ch)) {
            $state->Throw('Control characters are not allowed in strings');
        }
        $state->Advance(0);
        if ($ch == _codeQuote()) {
            return $state->MakeTokenFromBuffer(String, 0);
        }
        if ($ch == _codeBackSlash()) {
            $lastEscape = 1;
        }
    }
}

sub _ProcessNumber {
    my ($state) = @_;
    $state->SetTokenStart();
    my $phase = 'Beginning';
    while (1) {
        my $ch = $state->Current;
        my $handling = 'ValidAndConsumed';
        if ($phase eq 'Beginning') {
            if ($ch == _codeMinus()) {
                $phase = 'PastLeadingSign';
            } elsif ($ch == _codeZero()) {
                $phase = 'PastWhole';
            } elsif (_isDigit($ch)) {
                $phase = 'PastFirstDigitOfWhole';
            } else {
                $handling = 'InvalidatesToken';
            }
        }
        elsif ($phase eq 'PastLeadingSign') {
            if (!_isDigit($ch)) {
                $handling = 'InvalidatesToken';
            } elsif ($ch == _codeZero()) {
                $phase = 'PastWhole';
            } else {
                $phase = 'PastFirstDigitOfWhole';
            }
        }
        elsif ($phase eq 'PastFirstDigitOfWhole') {
            if ($ch == _codeDecimal()) {
                $phase = 'PastDecimalPoint';
            } elsif ($ch == _codeLittleE() || $ch == _codeBigE()) {
                $phase = 'PastE';
            } elsif (!_isDigit($ch)) {
                $handling = 'StartOfNewToken';
            }
        }
        elsif ($phase eq 'PastWhole') {
            if ($ch == _codeDecimal()) {
                $phase = 'PastDecimalPoint';
            } elsif ($ch == _codeLittleE() || $ch == _codeBigE()) {
                $phase = 'PastE';
            } else {
                $handling = 'StartOfNewToken';
            }
        }
        elsif ($phase eq 'PastDecimalPoint') {
            if (_isDigit($ch)) {
                $phase = 'PastFirstDigitOfFractional';
            } else {
                $handling = 'InvalidatesToken';
            }
        }
        elsif ($phase eq 'PastFirstDigitOfFractional') {
            if ($ch == _codeLittleE() || $ch == _codeBigE()) {
                $phase = 'PastE';
            } elsif (!_isDigit($ch)) {
                $handling = 'StartOfNewToken';
            }
        }
        elsif ($phase eq 'PastE') {
            if ($ch == _codePlus() || $ch == _codeMinus()) {
                $phase = 'PastExpSign';
            } elsif (_isDigit($ch)) {
                $phase = 'PastFirstDigitOfExponent';
            } else {
                $handling = 'InvalidatesToken';
            }
        }
        elsif ($phase eq 'PastExpSign') {
            if (_isDigit($ch)) {
                $phase = 'PastFirstDigitOfExponent';
            } else {
                $handling = 'InvalidatesToken';
            }
        }
        elsif ($phase eq 'PastFirstDigitOfExponent') {
            if (!_isDigit($ch)) {
                $handling = 'StartOfNewToken';
            }
        }

        if ($handling eq 'InvalidatesToken') {
            $state->Throw('Bad character while processing number');
        }
        if ($handling eq 'StartOfNewToken') {
            return $state->MakeTokenFromBuffer(Number, 0);
        }
        if (!$state->AtEnd) {
            $state->Advance(0);
            next;
        }
        if ($phase eq 'PastFirstDigitOfWhole' || $phase eq 'PastWhole' || $phase eq 'PastFirstDigitOfFractional' || $phase eq 'PastFirstDigitOfExponent') {
            return $state->MakeTokenFromBuffer(Number, 0);
        }
        $state->Throw('Unexpected end of input while processing number');
    }
}

sub _codeSpace { ord(' ') }
sub _codeLF { ord("\n") }
sub _codeCR { ord("\r") }
sub _codeTab { ord("\t") }
sub _codeSlash { ord('/') }
sub _codeStar { ord('*') }
sub _codeBackSlash { ord('\\') }
sub _codeQuote { ord('"') }
sub _codeOpenCurly { ord('{') }
sub _codeCloseCurly { ord('}') }
sub _codeOpenSquare { ord('[') }
sub _codeCloseSquare { ord(']') }
sub _codeColon { ord(':') }
sub _codeComma { ord(',') }
sub _codePlus { ord('+') }
sub _codeMinus { ord('-') }
sub _codeDecimal { ord('.') }
sub _codeZero { ord('0') }
sub _codeNine { ord('9') }
sub _codeLittleA { ord('a') }
sub _codeBigA { ord('A') }
sub _codeLittleB { ord('b') }
sub _codeLittleE { ord('e') }
sub _codeBigE { ord('E') }
sub _codeLittleF { ord('f') }
sub _codeBigF { ord('F') }
sub _codeLittleN { ord('n') }
sub _codeLittleR { ord('r') }
sub _codeLittleT { ord('t') }
sub _codeLittleU { ord('u') }

sub _isDigit { my ($c)=@_; return defined $c && $c >= _codeZero() && $c <= _codeNine(); }
sub _isHex {
    my ($c)=@_;
    return (_isDigit($c))
        || ($c >= _codeLittleA() && $c <= _codeLittleF())
        || ($c >= _codeBigA() && $c <= _codeBigF());
}
sub _isLegalAfterBackslash {
    my ($c)=@_;
    return ($c==_codeQuote() || $c==_codeBackSlash() || $c==_codeSlash() || $c==_codeLittleB() || $c==_codeLittleF() ||
        $c==_codeLittleN() || $c==_codeLittleR() || $c==_codeLittleT() || $c==_codeLittleU());
}
sub _isControl {
    my ($c)=@_;
    return ($c >= 0x00 && $c <= 0x1F) || ($c==0x7F) || ($c>=0x80 && $c<=0x9F);
}

1;
