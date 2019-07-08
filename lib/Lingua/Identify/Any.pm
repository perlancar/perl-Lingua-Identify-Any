package Lingua::Identify::Any;

# DATE
# VERSION

use 5.010_001;
use strict;
use warnings;
use Log::ger;

use Exporter qw(import);
our @EXPORT_OK = qw(detect_text_language);

our %SPEC;

our @BACKENDS = (
    'Lingua::Identify',
    #'Lingua::Identify::CLD',
    #'WebService::LanguageDetect',
);

$SPEC{detect_text_language} = {
    v => 1.1,
    summary => 'Detect language of text using one of '.
        'several available backends',
    description => <<'_',

Backends will be tried in order. When a backend is not available, or when it
fails to detect the language, the next backend will be tried. Currently

_
    args => {
        text => {
            schema => 'str*',
            req => 1,
            pos => 0,
        },
        backends => {
            schema => ['array*', of=>['str*', in=>\@BACKENDS]],
        },
        try_remote_backends => {
            schema => 'bool*',
        },
    },
};
sub detect_text_language {
    my %args = @_;

    my $try_remote_backends = $args{try_remote_backends};
    my @backends = (
        'Lingua::Identify',
        #'Lingua::Identify::CLD',
        #($try_remote_backends ? ('WebService::LanguageDetect') : ()),
    );
    @backends = @{ $args{backends} } if $args{backends};

    my $res = [500, "No backend was tried"];
  BACKEND:
    for my $backend (@backends) {
        if ($backend eq 'Lingua::Identify') {
            eval { require Lingua::Identify; 1 };
            if ($@) {
                log_debug "Skipping backend 'Lingua::Identify' because module is not available: $@";
                next BACKEND;
            }
            my @bres = Lingua::Identify::langof($args{text});
            if (!@bres) {
                log_debug "Backend 'Lingua::Identify' failed to detect language, trying the next backend";
                next BACKEND;
            }
            $res = [
                200, "OK",
                {
                    backend    => 'Lingua::Identify',
                    lang_code  => $bres[0],
                    confidence => $bres[1],
                },
            ];
            last BACKEND;
            # XXX put the other less probable language to func.*
        } else {
            log_warn "Unknown/unsupported backend '$backend'";
        }
    }

    $res;
}

1;
# ABSTRACT: Detect language of text using one of several available backends

=head1 SYNOPSIS

 use Lingua::Identify::Any qw(
     detect_text_language
 );

 my $res = detect_text_language(text => 'Blah blah blah');

Sample result:

 [200, "OK", {
     backend    => 'Lingua::Identify',
     lang_code  => "en",
     confidence => 0.78, # 1 would mean certainty
 }]


=head1 DESCRIPTION

This module offers a common interface to several language detection backends.


=head1 ENVIRONMENT

=head2 PERL_LINGUA_IDENTIFY_ANY_TRY_REMOTE_BACKENDS

Boolean. Set the default for L</detect_text_language>'s C<try_remote_backends>
argument.

If set to 1, will also include backends that query remotely, e.g.
L<WebService::LanguageDetect>.

=back
