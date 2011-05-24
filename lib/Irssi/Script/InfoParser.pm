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

=pod

=head1 SYNOPSIS

    use Irssi::Script::InfoParser;

    my $parser = Irssi::Script::InfoParser->new(file => $script);
    my $version = $parser->version;

    my @fields = $parser->metadata_fields;
    my $metadata = $parser->metadata;

    foreach my $name (@fields) {
        say "Value is $metadata->{$name}!";
    }

or

    # assuming the authors field is actually defined.

    my $parser = Irssi::Script::InfoParser->new(file => $script,
                                                split_authors => 0);

    return unless $parser->has_field('authors');

    my $authors_string = $parser->metadata->{authors};

    my $parser = Irssi::Script::InfoParser->new(file => $script,
                                                split_authors => 1);

    my $authors_arrayref = $parser->metadata->{authors};

=cut


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
      traits  => [qw/Hash/],
      is      => 'ro',
      isa     => 'HashRef',
      lazy    => 1,
      builder => '_build_metadata',
      writer  => '_set_metadata',
      handles => {
                  metadata_fields => 'keys',
                  has_field       => 'exists',
                 },
     );

has 'version'
  => (
      is      => 'ro',
      isa     => 'Str',
      writer  => '_set_version',
      lazy    => 1,
      builder => '_build_version',
     );

has 'split_authors'
  => (
      is       => 'ro',
      isa      => 'Bool',
      required => 1,
      default  => 0,
     );

has '_is_parsed'
  => (
      is      => 'rw',
      isa     => 'Bool',
      default => 0,
     );

sub _build_metadata {
    my $ret = $_[0]->_parse_unless_done;
    return $ret->{metadata};
}

sub _build_version {
    my $ret = $_[0]->_parse_unless_done;
    return $ret->{version};
}

sub _parse_unless_done {
    my ($self) = @_;
    return if $self->_is_parsed;

    my $ret = $self->parse;
    die "Parsing document failed" unless $ret;

    return $ret;
}


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

    my $return_value = { version => 'UNKNOWN',
                         metadata => {},
                       };;
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

            my $version = $self->process_version_buffer(\@ver_buf);

            if (defined $version) {
                $self->_set_version($version);
                $return_value->{version} = $version;
                _info("*** Version returned: $version");
            } else {
                _warn("*** version parsing failed");
            }
            @ver_buf = ();
        }
        if (@hash_buf > 3) {
            _debug("Going to parse metahash");
            _info("buffer: '" .
                  join(" _ ", map { $_->content } @hash_buf) . "'");

            my $meta = $self->process_irssi_buffer(\@hash_buf);
            if (defined $meta) {
                $self->_set_metadata($meta);
                $return_value->{metadata} = $meta;
            }
            @hash_buf = ();
        }

    }

    _trace('!!! finished statement processing loop');

    _info("version set to: " . $self->version);
    _info("parse() complete. Returning $return_value");
    $self->_is_parsed(1);

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
        return $version;
    }

    _warn('process_version_buffer(): returning false');
    return;
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
        # remove quotes.
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
    my ($self, $key) = @_;
    return $self->_is_keyword($key);
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
    my $key_quoted  = 0;
    my $concat_buf;

  PARSE:
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
                        next PARSE;
                    }
                }
                when (1) {
                    if (is_assign($token)) {
                        $preamble = 2;
                        _debug("Seen Assign, Setting preamble to 2");
                        next PARSE;
                    }
                }
                when (2) {
                    if (is_structure_start($token)) {
                        $preamble = 3;
                        _debug("Seen Structure Start, Setting premable to 3");

                        next PARSE;
                    }
                }
            }
        }
        _trace('past preamble');

        # TODO:
        # need to check if anyone has quoted their first words, or
        # used commas rather than fat-arrows for key/val separation.
        given ($state) {
            when (0) {
                my $tmp;
                if ($tmp = is_unquoted_word($token)) {
                    $key_quoted = 0;
                } elsif ($tmp = is_quoted_content($token)) {
                    $key_quoted = 1;
                }

                if ($tmp and $self->is_valid_info_hashkey($tmp)) {
                    $key = $tmp;
                    _debug("Word ok, key=$key. Mode set to 1");
                    $state = 1;
                    next PARSE;
                } else {
                    $tmp ||= '';
                    _warn("parse failure, '$tmp' not a valid key");
                    last PARSE;
                }
            }
            when (1) {

                if ((is_fat_arrow($token)) or
                    ($key_quoted == 1 and is_comma($token))) {

                    _debug("Mode 1 -> 2, Fat Arrow Delim (or comma)");
                    $state = 2;
                    next PARSE;
                }
            }
            when (2) {

                if ($concat_buf = is_quoted_content($token)) {
                    _debug("Mode 2 -> 3, Read quoted content");
                    if ($concat_next) {
                        $value = $value . $concat_buf;
                        $concat_next = 0;
                    } else {
                        $value = $concat_buf;
                    }
                    $state = 3;
                    next PARSE;
                }
            }
            when (3) {
                if (is_concat($token)) {
                    $concat_next = 1;
                    $state = 2;
                    _debug("Concat pending");
                    next PARSE;
                }

                if (is_comma($token) or is_structure_end($token)) {
                    _debug("Mode 3, read comma, saving $key => $value");

                    $hash->{$key} = $value;
                    $key = '';
                    $value = '';
                    $state = 0;
                    next PARSE;
                }
            }
            default {
                if (is_structure_end($token) and $state != 0) {
                    _warn("Something went wrong. " .
                          "Incomplete parsing: $state/$key/$value");
                } else {
                    last PARSE;
                }
            }
        }
    }

    unless ($state == 0) {
        _warn("incomplete parsing, left in state: $state");
        die;
    }
    $hash = $self->_postprocess_authors($hash) if $self->split_authors;
    return $hash;
}

sub _postprocess_authors {
    my ($self, $meta) = @_;
    _trace('_postprocess_authors() called');

    return unless exists $meta->{authors};

    my $authors_str = $meta->{authors};
    my @authors = split /\s*,\s*/, $authors_str;
    _trace('authors split into: ' . join(' | ', @authors));
    if (@authors > 1) {
        $meta->{authors} = \@authors;
    } else {
        $meta->{authors} = [ $authors_str ];
    }
    return $meta;
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
