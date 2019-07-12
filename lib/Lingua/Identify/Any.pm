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
    'Lingua::Identify::CLD',
    'Lingua::Identify',
    'WebService::DetectLanguage',
);

$SPEC{detect_text_language} = {
    v => 1.1,
    summary => 'Detect language of text using one of '.
        'several available backends',
    description => <<'_',

Backends will be tried in order. When a backend is not available, or when it
fails to detect the language, the next backend will be tried. Currently
supported backends:

* Lingua::Identify::CLD
* Lingua::Identify
* WebService::DetectLanguage (only when `try_remote_backends` is set to true)

_
    args => {
        text => {
            schema => 'str*',
            req => 1,
            pos => 0,
            cmdline_src => 'stdin_or_file',
        },
        backends => {
            schema => ['array*', of=>['str*', in=>\@BACKENDS]],
        },
        try_remote_backends => {
            schema => 'bool*',
        },
        dlcom_api_key => {
            summary => 'API key for detectlanguage.com',
            description => <<'_',

Only required if you use WebService::DetectLanguage backend.

_
            schema => 'str*',
        },
    },
    result => {
        schema => 'hash',
        description => <<'_',

Status: will return 200 status if detection is successful. Otherwise, will
return 400 if a specified backend is unknown/unsupported, or 500 if detection
has failed.

Payload: a hash with the following keys: `backend` (the backend name used to
produce the result), `lang_code` (str, 2-letter ISO language code), `confidence`
(float), `is_reliable` (bool).

_
    },
};
sub detect_text_language {
    my %args = @_;

    my $backends = $args{backends} //
        ($ENV{PERL_LINGUA_IDENTIFY_ANY_BACKENDS} ?
         [split /\s*,\s*/, $ENV{PERL_LINGUA_IDENTIFY_ANY_BACKENDS}] : undef);
    my $try_remote_backends = $args{try_remote_backends} //
        $ENV{PERL_LINGUA_IDENTIFY_ANY_TRY_REMOTE_BACKENDS};
    my $dlcom_api_key = $args{dlcom_api_key} //
        $ENV{PERL_LINGUA_IDENTIFY_ANY_DLCOM_API_KEY};
    my @backends = (
        'Lingua::Identify::CLD',
        'Lingua::Identify',
        ($try_remote_backends ? ('WebService::LanguageDetect') : ()),
    );
    @backends = @$backends if $backends;

    my $res = [500, "No backend was tried", {}, {
        'func.attempted_backends' => [],
    }];

  BACKEND:
    for my $backend (@backends) {
        if ($backend eq 'Lingua::Identify::CLD') {
            eval { require Lingua::Identify::CLD; 1 };
            if ($@) {
                log_debug "Skipping backend 'Lingua::Identify::CLD' because module is not available: $@";
                next BACKEND;
            }
            my $cld = Lingua::Identify::CLD->new;
            my @lang = $cld->identify($args{text});
            push @{$res->[3]{'func.attempted_backends'}}, 'Lingua::Identify::CLD';
            if (!@lang) {
                log_debug "Backend 'Lingua::Identify::CLD' failed to detect language";
                next BACKEND;
            }
            $res->[0] = 200;
            $res->[1] = "OK";
            $res->[2] = {
                backend     => 'Lingua::Identify::CLD',
                lang_code   => $lang[1],
                confidence  => $lang[2] / 100,
                is_reliable => $lang[3],
            };
            goto RETURN_RES;
            # XXX put the other less probable language to func.*
        } elsif ($backend eq 'Lingua::Identify') {
            eval { require Lingua::Identify; 1 };
            if ($@) {
                log_debug "Skipping backend 'Lingua::Identify' because module is not available: $@";
                next BACKEND;
            }
            my @bres = Lingua::Identify::langof($args{text});
            push @{$res->[3]{'func.attempted_backends'}}, 'Lingua::Identify';
            if (!@bres) {
                log_debug "Backend 'Lingua::Identify' failed to detect language, trying the next backend";
                next BACKEND;
            }
            $res->[0] = 200;
            $res->[1] = "OK";
            $res->[2] = {
                backend    => 'Lingua::Identify',
                lang_code  => $bres[0],
                confidence => $bres[1],
                is_reliable => 1,
            };
            goto RETURN_RES;
            # XXX put the other less probable language to func.*
        } elsif ($backend eq 'WebService::DetectLanguage') {
            eval { require WebService::DetectLanguage; 1 };
            if ($@) {
                log_debug "Skipping backend 'WebService::DetectLanguage' because module is not available: $@";
                next BACKEND;
            }
            $dlcom_api_key or do {
                log_warn "Backend 'WebService::DetectLanguage' cannot be used, API key (dlcom_api_key) not provided, trying the next backend";
                next BACKEND;
            };
            my $api = WebService::DetectLanguage->new(key => $dlcom_api_key);
            my @possib = $api->detect($args{text});
            push @{$res->[3]{'func.attempted_backends'}}, 'WebService::DetectLanguage';
            if (!@possib) {
                log_debug "Backend 'WebService::DetectLanguage' failed to detect language, trying the next backend";
                next BACKEND;
            }
            $res->[0] = 200;
            $res->[1] = "OK";
            $res->[2] = {
                backend     => 'WebService::DetectLanguage',
                lang_code   => $possib[0]->language->code,
                confidence_raw => $possib[0]->confidence, # not a range/percentage, the more text is being fed, the higher the confidence
                confidence  => undef,
                is_reliable => $possib[0]->is_reliable,
            };
            goto RETURN_RES;
            # XXX put the other less probable language to func.*
        } else {
            $res->[0] = 400;
            $res->[1] = "Unknown/unsupported backend '$backend'";
            goto RETURN_RES;
        }
    }

    $res->[1] = 'No backends were able to detect the language'
        if @{ $res->[3]{'func.attempted_backends'} };
  RETURN_RES:
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
     backend     => 'Lingua::Identify',
     lang_code   => "en",
     confidence  => 0.78, # 1 would mean certainty
     is_reliable => 1,
 }]


=head1 DESCRIPTION

This module offers a common interface to several language detection backends.


=head1 ENVIRONMENT

=head2 PERL_LINGUA_IDENTIFY_ANY_BACKENDS

String. Comma-separated list of backends.

=head2 PERL_LINGUA_IDENTIFY_ANY_TRY_REMOTE_BACKENDS

Boolean. Set the default for L</detect_text_language>'s C<try_remote_backends>
argument.

If set to 1, will also include backends that query remotely, e.g.
L<WebService::DetectLanguage>.

=head2 PERL_LINGUA_IDENTIFY_ANY_DLCOM_API_KEY

String. Set the default for L</detect_text_language>'s C<dlcom_api_key>.

=cut
