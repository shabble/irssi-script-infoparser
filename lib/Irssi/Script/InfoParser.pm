package Irssi::Script::InfoParser;

use strict;
use warnings;
use v5.12;

use Moose;
use namespace::autoclean;

use Log::Any qw($log);

use PPI;
use PPI::Document;
use PPI::Dumper;
use Data::Dumper;

=pod

=head1 NAME

Irssi::Script::InfoParser - Extract information from the C<$VERSION> and
C<%IRSSI> headers of an Irssi script.

=head1 DESCRIPTION

TODO

=head1 ATTRIBUTES

=cut


has 'file'
  => (
      is       => 'rw',
      isa      => 'Str',
      required => 1,
      default => '',
     );

has 'ppi_doc'
  => (
      is      => 'rw',
      isa     => 'PPI::Document',
      builder => '_load_ppi_doc',
      lazy    => 1,
     );

has 'hash_keywords'
  => (
      is      => 'ro',
      isa     => 'HashRef',
      traits  => [qw/Hash/],
      builder => '_build_keyword_list',
      handles => {
                  is_keyword => 'exists',
                 },
     );

has 'probable_versions'
  => (
      is      => 'rw',
      isa     => 'ArrayRef',
      traits  => [qw/Array/],
      default => sub { [] },
      handles => {
                  add_to_probables => 'push',
                 },

     );

has 'metadata'
  => (
      is      => 'rw',
      isa     => 'HashRef',
      default => sub { {} },

     );

has 'version'
  => (
      is      => 'ro',
      isa     => 'Str',
      writer  => '_set_version',
      default => 'unknown',
     );

=pod

=head1 METHODS

=cut

sub load_new_file {
    my ($self, $c,  $file) = @_;

    $self->file ($file);
    $c->log->info("Loading new file: $file");
    $self->ppi_doc($self->_load_ppi_doc());
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

sub verify_document {
    my ($self) = @_;
    my $doc = $self->ppi_doc;

    return $doc->complete();
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

    my $doc = $self->ppi_doc;

    my $VERSION;
    my $IRSSI;

    $self->probable_versions([]);


    my $statements = $doc->find('PPI::Statement');
    #say 'Found ' . scalar @$statements . ' statements to process';
    foreach my $s (@$statements) {
        #say "Statement: " . $s->class;
        my @tokens = $s->tokens();
        #say "  Contains " . scalar(@tokens) . " tokens";
        my @sig = grep { $_->significant  } @tokens;
        #say "    Of which " . scalar(@sig) . " are significant";


        my $start_hash = 0;
        my $start_ver  = 0;
        my @ver_buf    = ();
        my @hash_buf   = ();

        my $i = 0; my $max = $#sig;
        foreach my $t (@sig) {
            $i++;
            #say "Token: " . $t->class . " : " . $t->content;

            if ($t->class =~ m/Symbol/ and $t->content =~ m/\%IRSSI/) {
                $start_hash = 1;
                # say "### starting HASH here";
            }

            if ($start_hash) {
                push @hash_buf, $t;
            }

            if ($t->class =~ m/Symbol/ and $t->content =~ m/\$VERSION/) {
                $start_ver = 1;
                #say "**Starting version here";
            }
            if ($start_ver) {
                push @ver_buf, $t;
            }
            if ($i == $max) {
                if (scalar @ver_buf) {
                    #   say "Our Version  Buffer Contains: ";
                    #  say join(", ", map { $_->content } @ver_buf);
                    $VERSION = $self->process_version_buffer(@ver_buf);
                    $VERSION //= 'unknown';
                    $self->_set_version($VERSION);
                }

                if (scalar @hash_buf) {
                    #  say "Our IRSSI buffer contains: ";
                    #  say join(", ", map { $_->content } @hash_buf);
                    $IRSSI = $self->process_irssi_buffer(@hash_buf);
                    $self->metadata($IRSSI);
                }
            }
        }
    }
}

sub process_version_buffer {
    my ($self, @buf) = @_;

    my $probable_version;

    my $score;
    foreach my $tok (@buf) {
        if ($tok->class =~ m/Symbol/ && $tok->content =~ m/VERSION/) {
            $score++;
        }
        if ($tok->class =~ m/Operator/ && $tok->content =~ m/=/) {
            $score++;
        }
        if ($tok->class =~ m/Quote/) {
            $score++;
        }
        if ($tok->content =~ m/((?:[0-9].?)+)/) {
            $score += length($1);
            $score -= int (length($tok->content) / 10);
            if ($score > 4) {
                $probable_version = $1;
                #  say "Probable Version Number: $probable_version, score: $score";
                $self->add_to_probables([$probable_version,
                                         $score, $tok->line_number]);
            }
        }
    }
    # sort by score;
    my @tmp = sort { $b->[1] <=> $a->[1] } @{ $self->probable_versions };

    if (scalar(@tmp) != 0) {
        my ($v, $s, $l) = @{$tmp[0]};

        my $version = $v if defined($l) and $l < 50;

        $version =~ s/^['"]//;
        $version =~ s/['"]$//;

        #say "*" x 20;
        #say "Extracted VERSION: $version";
        #say "*" x 20;
        return $version;
    }
    return 'UNKNOWN';

}

sub is_comma {
    my ($token) = @_;
    return (($token->class eq 'PPI::Token::Operator') and ($token->content eq ','))
}

sub is_assign {
    my ($token) = @_;
    return (($token->class eq 'PPI::Token::Operator') and ($token->content eq '='))
}

sub is_fat_arrow {
    my ($token) = @_;
    return (($token->class eq 'PPI::Token::Operator') and ($token->content eq '=>'))
}

sub is_concat {
    my ($token) = @_;
    return (($token->class eq 'PPI::Token::Operator') and ($token->content eq '.'))
}

sub is_structure_start {
    my ($token) = @_;
    return (($token->class eq 'PPI::Token::Structure') and ($token->content eq '('))
}

sub is_structure_end {
    my ($token) = @_;
    return (($token->class eq 'PPI::Token::Structure') and ($token->content eq ')'))
}

sub is_unquoted_word {          # only hash keys are unquoted here.
    my ($token) = @_;
    return ($token->class eq 'PPI::Token::Word')?$token->content():();
}

sub is_valid_keyhash {
    my ($self, $token) = @_;
    return $self->is_keyword($token->content);
}

sub is_quoted_content {
    my ($token) = @_;
    if ($token->class =~ m/^PPI::Token::Quote::(Double|Single)/) {
        my $type = ($1 eq 'Double') ? '"' : "'";
        my $content = $token->content();
        $content =~ s/^$type//; $content =~ s/$type$//;
        #say "Content >>$content<<";
        return $content;
    }
    return ();
}

sub is_IRSSI_start_symbol {
    my ($token) = @_;
    return (($token->class =~ m/Symbol/) and ($token->content =~ m/\%IRSSI/));
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

        if ($mode == 0 and is_unquoted_word($tok) and $self->is_valid_keyhash($tok)) {
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


=pod

=head1 AUTHOR

Tom Feist L<mailto:shabble+irssi@metavore.org>

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

__PACKAGE__->meta->make_immutable;

1;
