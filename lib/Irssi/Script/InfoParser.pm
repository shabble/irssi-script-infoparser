package Irssi::Script::InfoParser;
# ABSTRACT: Extract information from the C<$VERSION> and C<%IRSSI> headers of an Irssi script.

use strict;
use warnings;
use v5.12;

use Moose;
use namespace::autoclean;
use feature qw/switch/;

use Log::Any qw($log);

use PPI;
use PPI::Document;
use PPI::Dumper;
use Data::Dumper;


has 'file'
  => (
      is       => 'rw',
      isa      => 'Str',
      required => 1,
     );

has '_ppi_doc'
  => (
      is      => 'rw',
      isa     => 'PPI::Document',
      builder => '_load_ppi_doc',
      lazy    => 1,
     );

has '_hash_keywords'
  => (
      is      => 'ro',
      isa     => 'HashRef',
      traits  => [qw/Hash/],
      builder => '_build_keyword_list',
      handles => {
                  _is_keyword => 'exists',
                 },
     );

has 'metadata'
  => (
      is      => 'ro',
      isa     => 'HashRef',
      default => sub { {} },
      writer  => '_set_metadata',
     );

has 'version'
  => (
      is      => 'ro',
      isa     => 'Str',
      writer  => '_set_version',
      default => 'cake',
     );

sub _load_ppi_doc {
    my ($self) = @_;
    my $file = $self->file;
    my $doc = PPI::Document->new($file, readonly => 1);

    if (not defined $doc) {
        die "Exception parsing $file: $!"
    }

    if ($doc->errstr) {
        die "Exception parsing $file: " . $doc->errstr;
    }
    return $doc;
}

sub verify_document_complete {
    my ($self) = @_;
    my $doc = $self->_ppi_doc;

    return $doc->complete;
}

sub _build_keyword_list {
    my @keywords =
      ("authors", "contact", "name", "description", "licence",
       "license", "changed", "url",  "commands",    "changes",
       "modules", "sbitems", "bugs", "url_ion",     "note",
       "patch",   "original_authors","original_contact",
       "contributors",
      );

    my $keyhash = {};
    $keyhash->{$_}++ for (@keywords);

    return $keyhash;
}

# look for sequences of Symbol, Operator, Quote, Statement
sub parse {
    my ($self) = @_;
    _info('Entering parse()');

    my $doc = $self->_ppi_doc;
    die "Cannot parse an incomplete document"
      unless $self->verify_document_complete;

    my $return_value = 0;
    my @ver_buf;
    my @hash_buf;


    my $statements = $doc->find('PPI::Statement');
    _trace('Found ' . scalar @$statements . ' statements to process');

    _trace('!!! starting statement processing loop');
    foreach my $stmt (@$statements) {
        my $debug_str = "Statement: " . $stmt->class;

        my @tokens = $stmt->tokens;
        $debug_str .= " Contains " . scalar(@tokens) . " tokens";

        my @significant = grep { $_->significant } @tokens;
        $debug_str .= " Of which " . scalar(@significant) . " are significant";

        _trace($debug_str);

        my $collect_hash_tokens     = 0;
        my $collect_version_tokens  = 0;

        _trace('entering significant token capture loop');
        foreach my $token (@significant) {
            _trace("Token: " . $token->class . ': ' . $token->content);

            if (is_IRSSI_start_symbol($token)) {
                $collect_hash_tokens = 1;
                _trace("### starting HASH here");
            }

            if ($collect_hash_tokens) {
                push @hash_buf, $token;
            }

            if (is_VERSION_start_symbol($token)) {
                $collect_version_tokens = 1;
                _trace("**Starting version buffering here");
            }

            if ($collect_version_tokens) {
                push @ver_buf, $token;
            }
        }
        _trace('finished significant token capture loop');

        # minimum of '$VERSION, =, <value>, ;' = 4 tokens.
        if (@ver_buf > 3) {

            _debug("Going to parse version");
            _info("version buffer: '" .
                  join(" _ ", map { $_->content } @ver_buf) . "'");

            my $got_version = $self->process_version_buffer(\@ver_buf);

            if ($got_version) {
                $return_value = 1;
                _info("*** Version returned: $got_version");
            } else {
                _warn("*** version parsing failed");
            }
            @ver_buf = ();
        }
        if (@hash_buf > 3) {
            _debug("Going to parse metahash");
            _info("buffer: '" .
                  join(" _ ", map { $_->content } @hash_buf) . "'");

            $return_value = $self->process_irssi_buffer(\@hash_buf);
            @hash_buf = ();
        }

    }

    _trace('!!! finished statement processing loop');

    _info("version set to: " . $self->version);
    _info("parse() complete. Returning $return_value");
    return $return_value;
}

sub process_version_buffer {
    my ($self, $buffer) = @_;

    my $probable_version;
    # TODO: worth making some sort of enum-ish type for the states?
    # would aid clarity, I suppose.
    my $state = 0;
    my $score = 0;

    while(my $token = shift(@$buffer)) {
        my $class = $token->class;
        my $content = $token->content;

        given ($state) {

            when (0) {
                if ($class =~ m/Symbol/ && $content =~ m/VERSION/) {
                    $state = 1;
                    _trace("seen VERSION, moving to state 1");
                }
            }
            when (1) {
                if ($class =~ m/Operator/ and $content =~ m/=/) {
                    _trace("seen =, moving to state 2");
                    $state = 2;
                }
            }
            when (2) {

                _trace("In state 2, token content: " . $content);

                if ($probable_version = is_quoted_content($token)) {
                    _debug("got quoted content: $probable_version");
                    $state = 3;

                } elsif ($probable_version = is_number($token)) {
                    _debug("got quoted content: $probable_version");
                    $state = 3;

                } else {
                    _info("** failed parse");
                    $state = 0;
                    last;
                }
            }
            when (3) {

                _trace("In state 3, type: "
                       . $token->class . " content: " . $content);

                # TODO: I suppose it could not end with a semi-colon...?
                if (is_structure_semicolon($token)) {
                    $state = 4;
                    my $line_num = $token->line_number;
                    _info("Probable Version Number: $probable_version "
                          . "(score: $score) on line: $line_num");
                    last;
                }
            }
            default { $state = 0; }
        }
    }

    if (defined $probable_version and $state == 4) {

        # TODO: might want to think about something like this
        # re: line_num as a sanity check.
        # $version = $ver if defined($line) and $line < 50;

        my $version = $probable_version;

        # TODO: quoted_content should handle this already?
        $version =~ s/^['"]//;
        $version =~ s/['"]$//;

        _debug("Extracted VERSION: $version");
        $self->_set_version($version);

        return 1;
    }

    _warn('process_version_buffer(): returning false');
    return 0;
}

sub is_number {
    my ($token) = @_;
    my $is_num = ($token->class =~ m/^PPI::Token::Number/)
      ? 1
      : 0;

    if ($is_num) {
        _trace("is_number(): " . $token->content);
        return $token->content;
    } else {
        _trace("is_number(): returning false");
        return;
    }
}

sub is_comma {
    my ($token) = @_;
    return (($token->class   eq 'PPI::Token::Operator') and
            ($token->content eq ','))
}

sub is_assign {
    my ($token) = @_;
    return (($token->class   eq 'PPI::Token::Operator') and
            ($token->content eq '='))
}

sub is_fat_arrow {
    my ($token) = @_;
    return (($token->class   eq 'PPI::Token::Operator') and
            ($token->content eq '=>'))
}

sub is_concat {
    my ($token) = @_;
    return (($token->class   eq 'PPI::Token::Operator') and
            ($token->content eq '.'))
}

sub is_structure_start {
    my ($token) = @_;
    return (($token->class   eq 'PPI::Token::Structure') and
            ($token->content eq '('))
}

sub is_structure_end {
    my ($token) = @_;
    return (($token->class   eq 'PPI::Token::Structure') and
            ($token->content eq ')'))
}

sub is_structure_semicolon {
    my ($token) = @_;
    return (($token->class   eq 'PPI::Token::Structure') and
            ($token->content eq ';'))
}

sub is_unquoted_word {          # only hash keys are unquoted here.
    my ($token) = @_;
    return ($token->class eq 'PPI::Token::Word')
                                  ? $token->content
                                  : ();
}

sub is_quoted_content {
    my ($token) = @_;
    if ($token->class =~ m/^PPI::Token::Quote::(Double|Single)/) {
        my $type = ($1 eq 'Double') ? '"' : "'";
        my $content = $token->content;
        $content =~ s/^$type//; $content =~ s/$type$//;
        _trace("is_quoted_content(): Content '$content'");
        return $content;
    }
    _trace("is_quoted_content(): returning false.");
    return ();
}

sub is_IRSSI_start_symbol {
    my ($token) = @_;
    return (($token->class   =~ m/Symbol/) and
            ($token->content =~ m/\%IRSSI/));
}

sub is_VERSION_start_symbol {
    my ($token) = @_;
    return (($token->class   =~ m/Symbol/) and
            ($token->content =~ m/\$VERSION/));
}

sub is_valid_info_hashkey {
    my ($self, $token) = @_;
    return $self->_is_keyword($token->content);
}

sub process_irssi_buffer {
    my ($self, $buffer) = @_;
    #no warnings 'uninitialized';
    _trace('entering process_irssi_buffer()');
    # results accumulator.
    my $hash  = {};

    # state variables
    my $state    = 0;
    my $preamble = 0;


    my ($key, $value);
    my $concat_next = 0;
    my $z;

    while (my $token = shift(@$buffer)) {
        _info("Token: " . $token->class . " Content: " . $token->content);
        #_info("** Mode: $state, intro: $intro, $key => $value ");

        if ($preamble < 3) {
            _trace('in preamble');
            given ($preamble) {
                when (0) {
                    if (is_IRSSI_start_symbol($token)) {
                        $preamble = 1;
                        _debug("Seen Start, Setting preamble to 1");
                        next;
                    }
                }
                when (1) {
                    if (is_assign($token)) {
                        $preamble = 2;
                        _debug("Seen Assign, Setting preamble to 2");
                        next;
                    }
                }
                when (2) {
                    if (is_structure_start($token)) {
                        $preamble = 3;
                        _debug("Seen Structure Start, Setting premable to 3");

                        next;
                    }
                }
            }
        }
        _trace('past preamble');

        # _info("Token: " . $token->class . " Content: " . $token->content);
        # _info("** Mode: $state, intro: $intro, $key => $value ");

        # TODO:
        # need to check if anyone has quoted their first words, or
        # used commas rather than fat-arrows for key/val separation.
        given ($state) {
            when (0) {
                if (is_unquoted_word($token) and
                    $self->is_valid_info_hashkey($token)) {
                    $key = $token->content;

                    _debug("Word content is good, key=$key. Mode set to 1");
                    $state = 1;
                    next;
                }
            }
            when (1) {

                if (is_fat_arrow($token)) {
                    _debug("Mode 1 -> 2, Fat Arrow Delim");
                    $state = 2;
                    next;
                }
            }
            when (2) {

                if ($z = is_quoted_content($token)) {
                    _debug("Mode 2 -> 3, Read quoted content");
                    if ($concat_next) {
                        $value = $value . $z;
                        $concat_next = 0;
                    } else {
                        $value = $z;
                    }
                    $state = 3;
                    next;
                }
            }
            when (3) {
                if (is_concat($token)) {
                    $concat_next = 1;
                    $state = 2;
                    _debug("Concat pending");
                    next;
                }

                if ((is_comma($token) or is_structure_end($token))) {
                    _debug("Mode 3, read comma, saving $key => $value");

                    $hash->{$key} = $value;
                    $key = undef; $value = undef;
                    $state = 0;
                    next;
                }
            }
            default {
                if (is_structure_end($token) and $state != 0) {
                    _warn("Something went wrong. " .
                          "Incomplete parsing: $state/$key/$value");
                } else {
                    last;
                }
            }
        }
    }
    my $ret = $self->_set_metadata($hash);
    return scalar(keys %$ret);
}


sub _trace {
    if (@_ > 1) {
        $log->tracef(@_);
    } else {
        $log->trace($_[0]);
    }
}

sub _info {
    if (@_ > 1) {
        $log->infof(@_);
    } else {
        $log->info($_[0]);
    }
}

sub _debug {
    if (@_ > 1) {
        $log->debugf(@_);
    } else {
        $log->debug($_[0]);
    }
}

sub _warn {
    if (@_ > 1) {
        $log->warnf(@_);
    } else {
        $log->warn($_[0]);
    }
}

__PACKAGE__->meta->make_immutable;

1;
