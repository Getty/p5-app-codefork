#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use Path::Tiny;
use App::codefork;

plan skip_all => 'file modes are not POSIX here' if $^O eq 'MSWin32';

my $tree = Path::Tiny->tempdir;
my %files = (
  'keep.sh'   => 0755,    # modified in place
  'Old.sh'    => 0755,    # renamed and modified
  'secret.pl' => 0600,    # modified in place, tighter than any umask leaves
  'Old.bin'   => 0750,    # pure rename (content has no match)
);
for my $name ( keys %files ) {
  $tree->child($name)->spew_raw( $name eq 'Old.bin' ? "x\n" : "Old\n" );
  $tree->child($name)->chmod( $files{$name} );
}
my $confdir = Path::Tiny->tempdir;
$confdir->child('fork.conf')->spew_raw("Old|New\n");

App::codefork->new(
  config => $confdir->child('fork.conf')->stringify,
  dir    => $tree->stringify,
)->apply_changes;

sub mode_of { sprintf '%04o', $tree->child( $_[0] )->stat->mode & 07777 }

is( $tree->child('keep.sh')->slurp_raw, "New\n", 'keep.sh was rewritten' );
is( mode_of('keep.sh'),   '0755', 'a modified file keeps its mode' );
is( mode_of('New.sh'),    '0755', 'a renamed and modified file keeps its mode' );
is( mode_of('secret.pl'), '0600', 'a tighter mode is kept as well' );
is( mode_of('New.bin'),   '0750', 'a pure rename keeps its mode' );
is_deeply(
  [ sort map { $_->basename } $tree->children ],
  [qw( New.bin New.sh keep.sh secret.pl )],
  'no temporary file is left behind',
);

done_testing;
