use strict;
use warnings;

use Test::More tests => 6;
use Irssi::Script::InfoParser;
use FindBin qw/$RealBin/;
use File::Spec;
use Test::Exception;

my $dir_name = [File::Spec->splitpath($0)]->[2];
$dir_name =~ s/\.t//;
my $samples_dir = File::Spec->catdir($RealBin, '/samples/', $dir_name);
#diag("name: $0, dir_name: $dir_name, samples dir: $samples_dir");


dies_ok( sub { Irssi::Script::InfoParser->new; }, 'file required' );

my $invalid_file = File::Spec->catfile($samples_dir, 'invalid.pl');
my $invalid_obj  = Irssi::Script::InfoParser->new(file => $invalid_file);

is (! $invalid_obj->verify_document_complete, 1, 'invalid file correctly detected');

dies_ok( sub { $invalid_obj->parse; }, 'parse fails on invalid document');

my $valid_file = File::Spec->catfile($samples_dir, 'valid.pl');
my $valid_obj  = Irssi::Script::InfoParser->new(file => $valid_file);

is ($valid_obj->verify_document_complete, 1, 'valid file correctly detected');

isa_ok($valid_obj->_ppi_doc, 'PPI::Document', 'valid file returns a PPI::Document');

lives_ok( sub { $valid_obj->parse; }, 'parse succeeds on valid document');

done_testing;
