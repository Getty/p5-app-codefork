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
  my @paths;
  $tree->visit( sub {
    my ( $path ) = @_;
    push @paths, $path->relative($tree)->stringify.( $path->is_dir ? '/' : '' );
  }, { recurse => 1 } );
  return [ sort @paths ];
}

{
  my ( $app, $tree ) = fork_for( ['Old|New'], 'Old/a.txt', 'Old/sub/b.txt', 'Keep/c.txt' );
  $app->apply_changes;
  is_deeply(
    tree_state($tree),
    [qw( Keep/ Keep/c.txt New/ New/a.txt New/sub/ New/sub/b.txt )],
    'a renamed directory is gone from its old place, deepest first',
  );
}

{
  my ( $app, $tree ) = fork_for( ['Old|New'], 'Old/a.txt', 'Old/.git/config' );
  $app->apply_changes;
  is_deeply(
    tree_state($tree),
    [qw( New/ New/a.txt Old/ Old/.git/ Old/.git/config )],
    'a directory that still holds something is never removed',
  );
}

{
  my ( $app, $tree ) = fork_for( ['Old|New'], 'Old/', 'Keep/', 'Keep/Old/', 'Full/Old/', 'Full/x.txt' );
  my $changes = $app->collect_changes;
  is_deeply(
    [ sort map { $_->{old_path}.' -> '.$_->{new_path} } @$changes ],
    [ 'Full/Old -> Full/New', 'Keep/Old -> Keep/New', 'Old -> New' ],
    'an empty directory whose name matches is a change',
  );
  my $diff = $app->generate_diff($changes);
  like( $diff, qr/^rename from Old\nrename to New$/m, 'the diff shows it as a rename' );
  $app->apply_changes($changes);
  is_deeply(
    tree_state($tree),
    [qw( Full/ Full/New/ Full/x.txt Keep/ Keep/New/ New/ )],
    'apply renames the empty directories and leaves the others alone',
  );
}

{
  my ( $app, $tree ) = fork_for( ['Old|New'], 'Old/a.txt', 'Old/empty/' );
  $app->apply_changes;
  is_deeply(
    tree_state($tree),
    [qw( New/ New/a.txt New/empty/ )],
    'an empty directory below a renamed one moves along',
  );
}

{
  my ( $app, $tree ) = fork_for( ['Old|New'], 'Old/', 'New/' );
  eval { $app->collect_changes };
  like( $@, qr/New \(from Old\) already exists/, 'an empty directory is not renamed onto an existing one' );
  is_deeply( tree_state($tree), [qw( New/ Old/ )], 'the tree is untouched' );
}

done_testing;
