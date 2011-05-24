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
      ("authors", "contact", "name", "description",
       "licence", "license", "url", "changed",
       "original_authors", "original_contact",
       "commands", "changes", "modules",
       "sbitems", "contributors", "bugs",
       "url_ion", "note", "patch",
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
    foreach my $s (@$statements) {
        my $debug_str = "Statement: " . $s->class;

        my @tokens = $s->tokens();
        $debug_str .= " Contains " . scalar(@tokens) . " tokens";

        my @sig = grep { $_->significant } @tokens;
        $debug_str .= " Of which " . scalar(@sig) . " are significant";

        _trace($debug_str);

        my $start_hash = 0;
        my $start_ver  = 0;

        my $i = 0;
        _trace('entering significant token capture loop');
        foreach my $t (@sig) {
            $i++;
            _trace("Token: " . $t->class . " : " . $t->content);

            if ($t->class =~ m/Symbol/ and $t->content =~ m/\%IRSSI/) {
                $start_hash = 1;
                _trace("### starting HASH here");
            }

            if ($start_hash) {
                push @hash_buf, $t;
            }

            if ($t->class =~ m/Symbol/ and $t->content =~ m/\$VERSION/) {
                $start_ver = 1;
                _trace("**Starting version buffering here");
            }

            if ($start_ver) {
                push @ver_buf, $t;
            }
        }
        _trace('finished significant token capture loop');

        # minimum of '$VERSION, =, <value>'
        if (@ver_buf >= 3) {

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
    }
    _trace('!!! finished statement processing loop');


    if (scalar @hash_buf) {
        #  say "Our IRSSI buffer contains: ";
        #  say join(", ", map { $_->content } @hash_buf);
        my $irssi = $self->process_irssi_buffer(@hash_buf);
        $self->_set_metadata($irssi);
        $return_value = 1;
    }

    _info("version set to: " . $self->version);
    _info("parse() complete. Returning $return_value");
    return $return_value;
}

sub process_version_buffer {
    my ($self, $buffer) = @_;

    my $probable_version;
    my $state = 0;
    my $score = 0;

    foreach my $tok (@$buffer) {
        if ($tok->class =~ m/Symbol/ && $tok->content =~ m/VERSION/) {
            $state = 1;
            _trace("seen VERSION, moving to state 1");
            next;
        }

        if ($state == 1 and
            $tok->class =~ m/Operator/ and
            $tok->content =~ m/=/) {
            _trace("seen =, moving to state 2");

            $state = 2;
            next;
        }

        if ($state == 2) {
            _trace("In state 2, token content: " . $tok->content);
            if ($probable_version = is_quoted_content($tok)) {
                _debug("got quoted content: $probable_version");
                $score = 1;
                $state = 3;
                next;
            } elsif ($probable_version = is_number($tok)) {
                _debug("got quoted content: $probable_version");
                $score = 2;
                $state = 3;
                next;
            } else {
                _info("** failed parse");
                $state = 0;
                last;
            }
        }

        if ($state == 3) {

            _trace("In state 3, type: "
                   . $tok->class . " content: " . $tok->content);

            # TODO: I suppose it could not end with a semi-colon...?
            if (is_structure_semicolon($tok) && $score > 0) {

                my $line_num = $tok->line_number;
                _info("Probable Version Number: $probable_version "
                      . "(score: $score) on line: $line_num");
            }

            $state = 0;
        }
    }

    if (defined $probable_version) {
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
                                  ? $token->content()
                                  : ();
}

sub is_quoted_content {
    my ($token) = @_;
    if ($token->class =~ m/^PPI::Token::Quote::(Double|Single)/) {
        my $type = ($1 eq 'Double') ? '"' : "'";
        my $content = $token->content();
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

sub is_valid_info_hashkey {
    my ($self, $token) = @_;
    return $self->_is_keyword($token->content);
}

sub process_irssi_buffer {
    my ($self, @buf) = @_;
    no warnings 'uninitialized';
    my $hash  = {};
    my $mode  = 0;
    my $intro = 0;
    my ($key, $value);
    my $concat_next = 0;
    my $z;
    while (my $tok = shift(@buf)) {
        #say "Token: " . $tok->class . " Content: " . $tok->content;
        #say "** Mode: $mode, intro: $intro, $key => $value ";

        if ($intro < 3) {
            if (is_IRSSI_start_symbol($tok) and $intro == 0) {
                $intro = 1;
                #say "Seen Start, Setting intro to 1";
                next;
            }
            if (is_assign($tok) and $intro == 1) {
                $intro = 2;
                #say "Seen Assign, Setting intro to 2";
                next;
            }

            if (is_structure_start($tok) and $intro == 2) {
                $intro = 3;
                #say "Seen Structure Start, Setting intro to 3";

                next;
            }
        }
        # #say "Token: " . $tok->class . " Content: " . $tok->content;
        # #say "** Mode: $mode, intro: $intro, $key => $value ";

        # TODO:
        # need to check if anyone has quoted their first words, or
        # used commas rather than fat-arrows for key/val separation.

        if ($mode == 0 and is_unquoted_word($tok) and
            $self->is_valid_info_hashkey($tok)) {
            $key = $tok->content;
            #say "Word content is good, key=$key. Mode set to 1";
            $mode = 1;
            next;
        }

        if ($mode == 1 and is_fat_arrow($tok)) {
            #say "Mode 1, Fat Arrow Delim";
            $mode = 2;
            next;
        }

        if ($mode == 2 and ($z = is_quoted_content($tok))) {
            #say "Mode 2, Read quoted content";
            if ($concat_next) {
                $value = $value . $z;
                $concat_next = 0;
            } else {
                $value = $z;
            }
            $mode = 3;
            next;
        }

        if ($mode == 3 and is_concat($tok)) {
            $concat_next = 1;
            $mode = 2;
            #say "Concat pending";
            next;
        }

        if ($mode == 3 and (is_comma($tok) or is_structure_end($tok))) {
            #say "Mode 3, read comma, saving $key => $value";

            $hash->{$key} = $value;
            $key = undef; $value = undef;
            $mode = 0;
            next;
        }


        if (is_structure_end($tok) and $mode != 0) {
            #say "Something went wrong. Incomplete parsing: $mode/$key/$value";
        } else {
            last;
        }
    }
    return $hash;

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
