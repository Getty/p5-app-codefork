#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use Path::Tiny;
use App::codefork;

my @keep;    # the config dirs live as long as the test

sub fork_for {
  my ( $rules, %files ) = @_;
  my $tree = Path::Tiny->tempdir;
  for my $name ( keys %files ) {
    $tree->child($name)->parent->mkpath;
    $tree->child($name)->spew_raw( $files{$name} );
  }
  my $confdir = Path::Tiny->tempdir;
  $confdir->child('fork.conf')->spew_raw( join( "\n", @$rules )."\n" );
  my $app = App::codefork->new(
    config => $confdir->child('fork.conf')->stringify,
    dir    => $tree->stringify,
  );
  push @keep, $confdir;
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
  my ( $app, $tree ) = fork_for( ['A|B'], 'A.txt' => 'one', 'B.txt' => 'two' );
  my $before = tree_state($tree);
  my $changes = eval { $app->collect_changes };
  like( $@, qr/B\.txt.*already exists/, 'rename onto an existing file is refused in the plan' );
  like( $@, qr/A\.txt/, 'the refusal names the source path' );
  ok( !defined $changes, 'no plan is returned' );
  eval { $app->generate_diff };
  like( $@, qr/B\.txt.*already exists/, 'the diff refuses it the same way' );
  eval { $app->apply_changes };
  like( $@, qr/B\.txt.*already exists/, 'apply without a plan refuses it the same way' );
  is_deeply( tree_state($tree), $before, 'the tree is untouched' );
}

{
  my ( $app, $tree ) = fork_for( ['[ab]\.txt|c.txt'], 'a.txt' => 'one', 'b.txt' => 'two' );
  my $before = tree_state($tree);
  eval { $app->collect_changes };
  like( $@, qr/a\.txt.*b\.txt.*c\.txt|both become c\.txt/s, 'two files mapping to the same path are refused' );
  like( $@, qr/a\.txt/, 'the refusal names the first source' );
  like( $@, qr/b\.txt/, 'the refusal names the second source' );
  eval { $app->apply_changes };
  ok( $@, 'apply refuses it as well' );
  is_deeply( tree_state($tree), $before, 'the tree is untouched' );
}

{
  # B.txt is renamed away to C.txt, so A.txt may take its place
  my ( $app, $tree ) = fork_for( [ '^B|C', '^A|B' ], 'A.txt' => 'one', 'B.txt' => 'two' );
  my $changes = $app->collect_changes;
  my %new = map { $_->{old_path} => $_->{new_path} } @$changes;
  is_deeply( \%new, { 'A.txt' => 'B.txt', 'B.txt' => 'C.txt' }, 'a chain of renames is planned' );
  $app->apply_changes($changes);
  is_deeply( tree_state($tree), { 'B.txt' => 'one', 'C.txt' => 'two' }, 'the chain applies without losing a file' );
}

{
  # A.txt and B.txt swap their names
  my ( $app, $tree ) = fork_for( [ '^A|X', '^B|A', '^X|B' ], 'A.txt' => 'one', 'B.txt' => 'two' );
  my $before = tree_state($tree);
  eval { $app->collect_changes };
  like( $@, qr/cycle/, 'a cycle of renames is refused in the plan' );
  is_deeply( tree_state($tree), $before, 'the tree is untouched' );
}

{
  my ( $app, $tree ) = fork_for( ['A|B'], 'A.txt' => 'A', 'X.txt' => 'A' );
  my $changes = $app->collect_changes;
  is( scalar @$changes, 2, 'content changes in place are no collision' );
}

done_testing;
