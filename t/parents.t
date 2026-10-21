#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use Path::Tiny;
use App::codefork;

my @keep;    # the config dirs live as long as the test

sub fork_for {
  my ( $rules, @paths ) = @_;
  my $tree = Path::Tiny->tempdir;
  for my $name (@paths) {
    $name =~ m{/$}
      ? $tree->child($name)->mkpath
      : do { $tree->child($name)->parent->mkpath; $tree->child($name)->spew_raw($name) };
  }
  my $confdir = Path::Tiny->tempdir;
  $confdir->child('fork.conf')->spew_raw( join( "\n", @$rules )."\n" );
  push @keep, $confdir;
  my $app = App::codefork->new(
    config => $confdir->child('fork.conf')->stringify,
    dir    => $tree->stringify,
  );
  return ( $app, $tree );
}

sub tree_state {
  my ( $tree ) = @_;
  my %state;
  $tree->visit( sub {
    my ( $path ) = @_;
    $state{ $path->relative($tree)->stringify } = $path->is_dir ? '<dir>' : $path->slurp_raw;
  }, { recurse => 1 } );
  return \%state;
}

{
  # AOld.txt sorts first and is renamed before Old/a.txt: a die in mkpath would be halfway
  my ( $app, $tree ) = fork_for( ['Old|New'], 'AOld.txt', 'Old/a.txt', 'New' );
  my $before = tree_state($tree);
  eval { $app->collect_changes };
  like( $@, qr{New/a\.txt \(from Old/a\.txt\) needs a directory New}, 'a new parent that is an existing file is refused' );
  eval { $app->apply_changes };
  like( $@, qr{needs a directory New}, 'apply refuses it as well' );
  is_deeply( tree_state($tree), $before, 'the tree is untouched' );
}

{
  # Old2/a becomes New/a while the file Old becomes New
  my ( $app, $tree ) = fork_for( [ 'Old2|New', '^Old$|New' ], 'Old', 'Old2/a' );
  my $before = tree_state($tree);
  eval { $app->collect_changes };
  like( $@, qr{New/a \(from Old2/a\) needs a directory New}, 'a new parent that is another new path is refused' );
  is_deeply( tree_state($tree), $before, 'the tree is untouched' );
}

{
  # the file New is renamed away first, then A/x can move to New/x
  my ( $app, $tree ) = fork_for( [ '^New$|New.txt', '^A$|New' ], 'A/x', 'New' );
  $app->apply_changes;
  is_deeply(
    tree_state($tree),
    { 'New' => '<dir>', 'New/x' => 'A/x', 'New.txt' => 'New.txt' },
    'a parent file that is renamed away makes room first',
  );
}

{
  # the empty directory New moves to Gone first, so A/x does not go along with it
  my ( $app, $tree ) = fork_for( [ '^New$|Gone', '^A$|New' ], 'A/x', 'New/' );
  $app->apply_changes;
  is_deeply(
    tree_state($tree),
    { 'Gone' => '<dir>', 'New' => '<dir>', 'New/x' => 'A/x' },
    'a parent directory that is renamed away moves first',
  );
}

done_testing;
