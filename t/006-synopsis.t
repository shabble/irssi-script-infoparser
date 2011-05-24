use strict;
use warnings;
use Test::More;

use Test::Differences;

use FindBin qw/$RealBin/;
use File::Spec;
use YAML::Any;
use Data::Dumper;
use Log::Any::Test;
use Log::Any qw/$log/;

use Irssi::Script::InfoParser;

# setup crap

my $tests = 0;

my $dir_name = [File::Spec->splitpath($0)]->[2];
$dir_name =~ s/\.t//;
my $samples_dir = File::Spec->catdir($RealBin, '/samples/', $dir_name);

my $truth_file = File::Spec->catfile($samples_dir, 'values.yml');
ok(-f $truth_file, $truth_file . ": truth file exists"); $tests++;

my $truth_data = YAML::Any::LoadFile($truth_file);
isa_ok($truth_data, 'HASH', 'truth data loaded');        $tests++;

my $correct = $truth_data;

my $version = $truth_data->{version};
delete $truth_data->{version};

my $script = File::Spec->catfile($samples_dir, 'script.pl');

#-----------------------------------------------------------------
{
    my $parser = Irssi::Script::InfoParser->new(file => $script);
    is($parser->version, $version, 'version is correct');

    my @fields = $parser->metadata_fields;
    ok(@fields, 'has some fields');

    my $metadata = $parser->metadata;
    isa_ok($metadata, 'HASH', 'retrieved metadata hash ok');

    foreach my $name (@fields) {
        ok(exists($correct->{$name}), 'field exists');
        my $val = $metadata->{$name};
        is_deeply($metadata->{$name}, $correct->{$name}, 'field values match');
    }
}

#-----------------------------------------------------------------
{
    my $parser = Irssi::Script::InfoParser->new(file => $script,
                                                split_authors => 0);

    ok($parser->has_field('authors'), 'has authors field');
}
#-----------------------------------------------------------------
{
    my $parser = Irssi::Script::InfoParser->new(file => $script,
                                                split_authors => 1);

    ok($parser->has_field('authors'), 'has authors field');
    my $authors_arrayref = $parser->metadata->{authors};

    isa_ok($authors_arrayref, 'ARRAY', 'authors is arrayref');
    is(scalar @$authors_arrayref, 1, 'authors has a single value');

}

done_testing;
