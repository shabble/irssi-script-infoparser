use strict;
use warnings;

use Test::More;
use FindBin qw/$RealBin/;
use File::Spec;
use YAML::Any;
use Data::Dumper;
use Log::Any::Test;
use Log::Any qw/$log/;

use Irssi::Script::InfoParser;

my $tests = 0;

my $dir_name = [File::Spec->splitpath($0)]->[2];
$dir_name =~ s/\.t//;
my $samples_dir = File::Spec->catdir($RealBin, '/samples/', $dir_name);

my $truth_data = YAML::Any::LoadFile
  (File::Spec->catfile($samples_dir, 'values.yml'));
isa_ok($truth_data, 'HASH', 'truth data loaded');      $tests++;

my $correct;

$correct = $truth_data->{"set-1"}->{all};
isnt($correct, undef, 'set-1: truth value is valid');  $tests++;

foreach my $file (glob("$samples_dir/set-1/*.pl")) {
    $log->clear;
    my $f = [File::Spec->splitpath($file)]->[2];

    my $obj = obj($file);
    ok($obj->parse, "file $f parsed ok");
    isnt($obj->version, 'UNKNOWN', $f . ': got a value for $VERSION');
    my $ret =
    is  ($obj->version, $correct,  $f . ': got correct value for $VERSION');
    $tests += 3;
    dump_logs()  unless $ret;
}

foreach my $file (glob("$samples_dir/set-2/*.pl")) {
    $log->clear;

    my $f = [File::Spec->splitpath($file)]->[2];

    $correct = $truth_data->{'set-2'}->{$f};
    isnt($correct, undef, $f . ': truth value is valid');

    my $obj = obj($file);
    ok($obj->parse, "$f: parsed ok");

    isnt($obj->version, 'UNKNOWN', $f . ': got a value for $VERSION');
    my $ret =
    is  ($obj->version, $correct,  $f . ': got correct value for $VERSION');
    $tests += 4;
    dump_logs() unless $ret;
}

#rerun set-2 but without ->parse, to see if the autoparse works.

note('testing autoparse');

foreach my $file (glob("$samples_dir/set-2/*.pl")) {
    $log->clear;

    my $f = [File::Spec->splitpath($file)]->[2];

    $correct = $truth_data->{'set-2'}->{$f};
    isnt($correct, undef, $f . ': truth value is valid');

    my $obj = obj($file);

    isnt($obj->version, 'UNKNOWN', $f . ': got a value for $VERSION');
    my $ret =
    is  ($obj->version, $correct,  $f . ': got correct value for $VERSION');
    $tests += 3;
    dump_logs() unless $ret;
}


TODO: {
    local $TODO = "Need to eval these for proper results";
    # foreach my $file (glob("$samples_dir/set-3/*.pl")) {
    #     $correct = $truth_data->{'set-3'}->{$file};

    #     my $obj = obj($file);
    #     ok($obj->parse, "file $file parsed ok");
    #     is($obj->version, 'unknown', 'failed to parse version (expected)');
    #     $tests += 2;
    # }
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
    my @msgs = @{$msgs_aref};
    diag("Dumping Log info, num: " . scalar(@msgs));
    diag("-------------------------- start of messages ------------");

    foreach my $msg_href (@msgs) {
        my %msg_hash = %{$msg_href};
        my ($cat, $lvl, $msg) = @msg_hash{qw/category level message/};
        diag sprintf("[% 6s] %s", $lvl, $msg);
    }
    diag("-------------------------- end of messages ---------------");

    $log->clear;
    die;
    1;
}
