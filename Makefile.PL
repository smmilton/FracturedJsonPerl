use strict;
use warnings;

use ExtUtils::MakeMaker;

WriteMakefile(
    NAME             => 'FracturedJson',
    VERSION_FROM     => 'lib/FracturedJson.pm',
    ABSTRACT         => 'Format JSON/JSONC in a fractured style',
    AUTHOR           => 'Jesse Brooke (https://github.com/j-brooke), smmilton (https://github.com/smmilton)',
    LICENSE          => 'mit',
    MIN_PERL_VERSION => '5.010',
    EXE_FILES        => ['bin/fjson'],
    PREREQ_PM        => {
        'Encode'      => 0,
        'Getopt::Long'=> 0,
        'JSON::PP'    => 0,
        'List::Util'  => 0,
        'Test::More'  => 0,
    },
    META_MERGE       => {
        resources => {
            license    => ['http://opensource.org/licenses/MIT'],
            repository => 'https://github.com/smmilton',
        },
    },
    clean            => { FILES => 'FracturedJson-*' },
);
