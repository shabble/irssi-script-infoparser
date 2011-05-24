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

my $tests = 0;

my $dir_name = [File::Spec->splitpath($0)]->[2];
$dir_name =~ s/\.t//;
my $samples_dir = File::Spec->catdir($RealBin, '/samples/', $dir_name);

my $truth_file = File::Spec->catfile($samples_dir, 'values.yml');
ok(-f $truth_file, $truth_file . ": truth file exists"); $tests++;

my $truth_data = YAML::Any::LoadFile($truth_file);
isa_ok($truth_data, 'HASH', 'truth data loaded');        $tests++;

my $correct;

foreach my $filepath (glob("$samples_dir/*.pl")) {
    $log->clear;

    my $file = [File::Spec->splitpath($filepath)]->[2];
    my $ok = 1;

    $correct = $truth_data->{$file};
    isnt  ($correct, undef,  $file . ': truth value is valid');
    isa_ok($correct, 'HASH', $file . ': truth value is hashref');

    my $version = delete $correct->{version};
    isnt(exists($correct->{version}), 'version deleted from truth hash ok');

    my $obj = obj($filepath, 0);
    $ok = ok($obj->parse, "$file: parsed ok");

    is($obj->version, $version, $file . ': version is correct');

    my $meta = $obj->metadata;
    my @keys = sort keys %$meta;

    $ok = isa_ok($meta, 'HASH', $file . ': metadata is a hashref');
    $ok = cmp_ok(@keys, '>', 0, $file . ': has some keys');

    my @correct_keys = sort keys %$correct;
    $ok = eq_or_diff(\@keys, \@correct_keys, $file . ': keys match with expected');

    $tests += 8;

    foreach my $key (@keys) {
        my $m_val = $meta->{$key};
        my $c_val = $correct->{$key};
        $ok = eq_or_diff($m_val, $c_val,
                         "$file: values for key: '$key' are correct");
        $tests++;
    }

    dump_logs() unless $ok;
}


done_testing $tests;

sub obj {
    my ($name, $split) = @_;
    $split //= 1;
    my $obj = new_ok 'Irssi::Script::InfoParser', [file          => $name,
                                                   split_authors => $split];
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
    die "something failed" if $ENV{LOGGING_FATAL};
    1;
}
