#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use Path::Tiny;
use App::codefork;

my $cwd  = Path::Tiny->cwd;
my $tree = Path::Tiny->tempdir;
my $out  = Path::Tiny->tempdir;

my $umlaut = "\xc3\xa4";    # "ä" as UTF-8 bytes
$tree->child('Old.txt')->spew_raw( 'Old '.$umlaut."\n" );
$tree->child('fork.conf')->spew_raw("Old|New\n");

chdir $tree or die 'chdir '.$tree.': '.$!;
my $ok = eval {
  local *STDOUT;
  open STDOUT, '>', \my $stdout or die $!;
  App::codefork->run( 'output', $out->child('patch.diff')->stringify );
  1;
};
my $error = $@;
chdir $cwd or die 'chdir '.$cwd.': '.$!;
ok( $ok, 'output ran' ) or diag $error;

my $diff = $out->child('patch.diff')->slurp_raw;
like( $diff, qr/^-Old \Q$umlaut\E$/m, 'the removed line holds the original bytes' );
like( $diff, qr/^\+New \Q$umlaut\E$/m, 'the added line holds the original bytes' );
unlike( $diff, qr/\xc3\x83\xc2\xa4/, 'nothing is encoded twice' );

done_testing;
