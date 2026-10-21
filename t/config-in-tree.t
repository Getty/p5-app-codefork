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

{
  my $tree = Path::Tiny->tempdir;
  $tree->child('Old.txt')->spew_raw("Old\n");
  $tree->child('fork.conf')->spew_raw("Old|New\n");
  my ( $stdout, $error ) = run_in($tree);
  is( $error, undef, 'diff runs' );
  unlike( $stdout, qr/fork\.conf/, 'the default config is not in the diff' );
  ( $stdout, $error ) = run_in( $tree, 'apply' );
  is( $stdout, "Applied 1 change(s).\n", 'apply leaves the config out' );
  is( $tree->child('fork.conf')->slurp_raw, "Old|New\n", 'the config is not rewritten' );
  is( $tree->child('New.txt')->slurp_raw, "New\n", 'the rest of the tree is' );
}

{
  my $tree = Path::Tiny->tempdir;
  $tree->child('Old.txt')->spew_raw("Old\n");
  $tree->child('Old.conf')->spew_raw("Old|New\n");
  my ( $stdout, $error ) = run_in( $tree, 'apply', 'Old.conf' );
  is( $error, undef, 'apply with a named config runs' );
  ok( $tree->child('Old.conf')->exists, 'the config is not renamed' );
  ok( !$tree->child('New.conf')->exists, 'no renamed copy appears' );
  is( $tree->child('Old.conf')->slurp_raw, "Old|New\n", 'the config is not rewritten' );
}

{
  # the tree is reached through a symlink, the config by its real path
  my $tree = Path::Tiny->tempdir;
  $tree->child('sub')->mkpath;
  $tree->child('sub/fork.conf')->spew_raw("Old|New\n");
  $tree->child('sub/Old.txt')->spew_raw("Old\n");
  my $links = Path::Tiny->tempdir;
  my $link  = $links->child('tree');
  SKIP: {
    skip 'no symlinks here', 2 unless eval { symlink( $tree->stringify, $link->stringify ) };
    my $app = App::codefork->new(
      config => $tree->child('sub/fork.conf')->realpath->stringify,
      dir    => $link->stringify,
    );
    my @paths = map { $_->{old_path} } @{ $app->collect_changes };
    is_deeply( \@paths, ['sub/Old.txt'], 'the config is found by its real path' );
    $app = App::codefork->new(
      config => $link->child('sub/../sub/fork.conf')->stringify,
      dir    => $tree->realpath->stringify,
    );
    @paths = map { $_->{old_path} } @{ $app->collect_changes };
    is_deeply( \@paths, ['sub/Old.txt'], 'and through a symlink and a dotted path' );
  }
}

done_testing;
