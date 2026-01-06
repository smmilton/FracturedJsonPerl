package FracturedJson;

use strict;
use warnings;

our $VERSION = '1.0.0';

1;

=pod

=head1 NAME

FracturedJson - Format JSON/JSONC in a "fractured" style

=head1 SYNOPSIS

  use FracturedJson::Formatter;

  my $formatter = FracturedJson::Formatter->new();
  my $out = $formatter->Reformat($json_text, 0);

=head1 DESCRIPTION

This distribution provides a pure-Perl port of the FracturedJson formatter.
It can reformat JSON and (optionally) JSONC (JSON with comments) according to a
set of configurable formatting options.

The primary entry point is L<FracturedJson::Formatter>.

=head1 AUTHOR

Original author: https://github.com/j-brooke

Perl port: https://github.com/smmilton

=head1 LICENSE

MIT License. See C<LICENSE>.

=cut
