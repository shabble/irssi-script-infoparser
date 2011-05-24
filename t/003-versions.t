use strict;
use warnings;

use Test::More;
use Irssi::Script::InfoParser;
use FindBin qw/$RealBin/;
use File::Spec;
use YAML::Any;
use Data::Dumper;
use Log::Any::Test;
use Log::Any qw/$log/;

my $tests = 0;

my $dir_name = [File::Spec->splitpath($0)]->[2];
$dir_name =~ s/\.t//;
my $samples_dir = File::Spec->catdir($RealBin, '/samples/', $dir_name);

my $truth_data = YAML::Any::LoadFile
  (File::Spec->catfile($samples_dir, 'values.yml'));

is(ref ($truth_data), 'HASH', 'truth data loaded');

my $correct;

$correct = $truth_data->{"set-1"}->{all};

foreach my $file (glob("$samples_dir/set-1/*.pl")) {
    my $obj = obj($file);
    ok($obj->parse, "file $file parsed ok");
    isnt($obj->version, 'unknown', $file . ': got a value for $VERSION');
    is($obj->version, $correct, $file . ': got correct value for $VERSION');
    $tests += 3;
}

# diag(Dumper($truth_data->{'set-2'}));
# die;

foreach my $file (glob("$samples_dir/set-2/*.pl")) {

    my $f = [File::Spec->splitpath($file)]->[2];

    $correct = $truth_data->{'set-2'}->{$f};
    isnt($correct, undef, $f . ': truth value is valid');

    my $obj = obj($file);
    ok($obj->parse, "$f: parsed ok");

    isnt($obj->version, 'unknown', $f . ': got a value for $VERSION');
    is  ($obj->version, $correct,  $f . ': got correct value for $VERSION');
    $tests += 3;
    dump_logs();
}

TODO: {
    local $TODO = "Need to eval these for proper results";
    foreach my $file (glob("$samples_dir/set-3/*.pl")) {
        $correct = $truth_data->{'set-3'}->{$file};

        my $obj = obj($file);
        ok($obj->parse, "file $file parsed ok");
        is($obj->version, 'unknown', 'failed to parse version (expected)');
        $tests += 2;
    }
}


done_testing $tests;

sub obj {
    my ($name) = @_;
    my $obj = new_ok 'Irssi::Script::InfoParser', [file => $name];
    $tests++;
    return $obj;
}

sub dump_logs {
    my $msgs_aref = $log->msgs;
    foreach my $msg_href (@{$msgs_aref}) {
        my %msg_hash = %{$msg_href};
        my ($cat, $lvl, $msg) = @msg_hash{qw/category level message/};
        diag sprintf("[%5 s] %s", $lvl, $msg);
    }
    $log->clear;
}
