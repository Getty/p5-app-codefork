#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use Path::Tiny;
use App::codefork;

# run() works on the cwd: every call goes into a temp tree and back
sub run_in {
  my ( $dir, @args ) = @_;
  my $cwd = Path::Tiny->cwd;
  chdir $dir or die 'chdir '.$dir.': '.$!;
  my ( $stdout, $error ) = ('');
  {
    local *STDOUT;
    open STDOUT, '>', \$stdout or die $!;
    eval { App::codefork->run(@args); 1 } or $error = $@;
  }
  chdir $cwd or die 'chdir '.$cwd.': '.$!;
  return ( $stdout, $error );
}

sub new_tree {
  my $tree = Path::Tiny->tempdir;
  $tree->child('Old.txt')->spew_raw("Old\n");
  return $tree;
}

my $confdir = Path::Tiny->tempdir;
my $other   = $confdir->child('other.conf');
$other->spew_raw("Old|New\n");

{
  my $tree = new_tree();
  $tree->child('fork.conf')->spew_raw("Old|New\n");
  my ( $stdout, $error ) = run_in($tree);
  is( $error, undef, 'no argument: runs' );
  like( $stdout, qr/^rename from Old\.txt\nrename to New\.txt$/m, 'no argument: diff with fork.conf' );
  ok( $tree->child('Old.txt')->exists && !$tree->child('New.txt')->exists, 'no argument: nothing written' );
}

{
  my $tree = new_tree();
  my ( $stdout, $error ) = run_in( $tree, $other->stringify );
  is( $error, undef, 'config argument: runs' );
  like( $stdout, qr/^\+New$/m, 'config argument: diff with that config' );
  ok( $tree->child('Old.txt')->exists, 'config argument: nothing written' );
}

{
  my $tree = Path::Tiny->tempdir;
  $tree->child('x.txt')->spew_raw("x\n");
  my ( $stdout ) = run_in( $tree, $other->stringify );
  is( $stdout, "No changes.\n", 'nothing to change: says so' );
}

{
  my $tree = new_tree();
  my ( $stdout, $error ) = run_in( $tree, 'apply', $other->stringify );
  is( $error, undef, 'apply config: runs' );
  is( $stdout, "Applied 1 change(s).\n", 'apply config: reports the count' );
  is( $tree->child('New.txt')->slurp_raw, "New\n", 'apply config: written' );
  ok( !$tree->child('Old.txt')->exists, 'apply config: old file gone' );
}

{
  my $tree = new_tree();
  $tree->child('sub')->mkpath;
  $tree->child('sub/fork.conf')->spew_raw("Old|New\n");
  my ( $stdout, $error ) = run_in( $tree->child('sub'), 'apply' );
  is( $error, undef, 'apply: runs with fork.conf' );
  ok( $tree->child('Old.txt')->exists, 'apply: works on the cwd only' );
}

{
  my $tree = new_tree();
  my $out  = $confdir->child('two-args.diff');
  my ( $stdout, $error ) = run_in( $tree, 'output', $other->stringify, $out->stringify );
  is( $error, undef, 'output config file: runs' );
  is( $stdout, 'Wrote diff to '.$out."\n", 'output config file: reports the file' );
  like( $out->slurp_raw, qr/^\+New$/m, 'output config file: the diff is in the file' );
  ok( $tree->child('Old.txt')->exists, 'output config file: nothing else written' );
}

{
  my $tree = new_tree();
  $tree->child('fork.conf')->spew_raw("Old|New\n");
  my $out = $confdir->child('one-arg.diff');
  my ( undef, $error ) = run_in( $tree, 'output', $out->stringify );
  is( $error, undef, 'output file: runs with fork.conf' );
  like( $out->slurp_raw, qr/^\+New$/m, 'output file: the diff is in the file' );
}

{
  my $tree = new_tree();
  my ( undef, $error ) = run_in( $tree, 'output' );
  like( $error, qr/^output command requires a filename/, 'output without a file dies' );
}

{
  my $tree = new_tree();
  my ( undef, $error ) = run_in($tree);
  like( $error, qr/^Config file 'fork\.conf' not found/, 'missing fork.conf dies' );
  ( undef, $error ) = run_in( $tree, 'apply', 'nope.conf' );
  like( $error, qr/^Config file 'nope\.conf' not found/, 'missing config dies' );
  ok( $tree->child('Old.txt')->exists, 'nothing written' );
}

done_testing;
