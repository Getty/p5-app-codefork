#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use Path::Tiny;
use App::codefork;

plan skip_all => 'owners, modes and hard links are not POSIX here' if $^O eq 'MSWin32';

# the write of the new content fails halfway: the file is already truncated
package My::FailingWrite {
  use parent -norequire, 'App::codefork';
  sub _overwrite {
    my ( $self, $file, $content ) = @_;
    return $self->SUPER::_overwrite( $file, $content ) unless $content =~ /New/;
    $self->SUPER::_overwrite( $file, substr( $content, 0, 2 ) );
    die "disk full\n";
  }
}

my @keep;    # the temp dirs live as long as the test

sub fork_for {
  my ( %arg ) = @_;
  my $tree = Path::Tiny->tempdir;
  my $confdir = Path::Tiny->tempdir;
  $confdir->child('fork.conf')->spew_raw("Old|New\n");
  push @keep, $tree, $confdir;
  my $app = ( $arg{class} // 'App::codefork' )->new(
    config => $confdir->child('fork.conf')->stringify,
    dir    => $tree->stringify,
  );
  return ( $app, $tree );
}

sub ino  { ( stat $_[0] )[1] }
sub mode { sprintf '%04o', ( stat $_[0] )[2] & 07777 }
sub gid  { ( stat $_[0] )[5] }

# a group of ours that is not the one new files get
my ($other_gid) = grep { $_ != ( split ' ', $) )[0] } split ' ', $);

{
  my ( $app, $tree ) = fork_for();
  my $outside = Path::Tiny->tempdir;
  push @keep, $outside;
  $tree->child('keep.txt')->spew_raw("Old\n");
  $tree->child('Old.txt')->spew_raw("Old\n");
  link $tree->child('keep.txt'), $outside->child('keep.link') or die 'link: '.$!;
  link $tree->child('Old.txt'),  $outside->child('old.link')  or die 'link: '.$!;
  $app->apply_changes;
  is( $outside->child('keep.link')->slurp_raw, "New\n", 'a hard link sees the rewritten content' );
  is( ino( $tree->child('keep.txt') ), ino( $outside->child('keep.link') ), 'and is still the same file' );
  is( $outside->child('old.link')->slurp_raw, "New\n", 'renamed and modified: the link sees the content' );
  is( ino( $tree->child('New.txt') ), ino( $outside->child('old.link') ), 'and is still the same file' );
}

{
  my ( $app, $tree ) = fork_for();
  $tree->child('keep.sh')->spew_raw("Old\n");
  $tree->child('keep.sh')->chmod(0750);
  $tree->child('Old.pl')->spew_raw("Old\n");
  $tree->child('Old.pl')->chmod(0600);
  chown -1, $other_gid, $tree->child('keep.sh')->stringify, $tree->child('Old.pl')->stringify
    or die 'chgrp: '.$! if defined $other_gid;
  my %ino = map { $_ => ino( $tree->child($_) ) } qw( keep.sh Old.pl );
  $app->apply_changes;
  is( $tree->child('keep.sh')->slurp_raw, "New\n", 'rewritten' );
  is( ino( $tree->child('keep.sh') ), $ino{'keep.sh'}, 'in the same inode' );
  is( ino( $tree->child('New.pl') ), $ino{'Old.pl'}, 'a renamed file as well' );
  is( mode( $tree->child('keep.sh') ), '0750', 'mode kept' );
  is( mode( $tree->child('New.pl') ),  '0600', 'mode kept on a renamed file' );
  SKIP: {
    skip 'no second group to test with', 2 unless defined $other_gid;
    is( gid( $tree->child('keep.sh') ), $other_gid, 'group kept' );
    is( gid( $tree->child('New.pl') ),  $other_gid, 'group kept on a renamed file' );
  }
  is_deeply( [ sort map { $_->basename } $tree->children ], [qw( New.pl keep.sh )], 'no backup is left behind' );
}

SKIP: {
  skip 'only root can give a file to another owner - run as root to test it', 4 unless $> == 0;
  my ( $app, $tree ) = fork_for();
  $tree->child('keep.txt')->spew_raw("Old\n");
  $tree->child('Old.txt')->spew_raw("Old\n");
  chown 1, 1, $tree->child('keep.txt')->stringify, $tree->child('Old.txt')->stringify or die 'chown: '.$!;
  $app->apply_changes;
  is( ( stat $tree->child('keep.txt') )[4], 1, 'root: owner kept' );
  is( gid( $tree->child('keep.txt') ), 1, 'root: group kept' );
  is( ( stat $tree->child('New.txt') )[4], 1, 'root: owner kept on a renamed file' );
  is( gid( $tree->child('New.txt') ), 1, 'root: group kept on a renamed file' );
}

{
  my ( $app, $tree ) = fork_for();
  $tree->child('Old/sub')->mkpath;
  $tree->child('Old/sub/a.txt')->spew_raw("x\n");
  $tree->child('Old')->chmod(0750);
  $tree->child('Old/sub')->chmod(0700);
  chown -1, $other_gid, $tree->child('Old')->stringify or die 'chgrp: '.$! if defined $other_gid;
  $app->apply_changes;
  ok( !$tree->child('Old')->exists, 'the old directory is gone' );
  is( mode( $tree->child('New') ),     '0750', 'a directory created for a rename takes the old mode' );
  is( mode( $tree->child('New/sub') ), '0700', 'below it as well' );
  SKIP: {
    skip 'no second group to test with', 1 unless defined $other_gid;
    is( gid( $tree->child('New') ), $other_gid, 'and the old group' );
  }
}

SKIP: {
  skip 'root can write a read-only file', 3 if $> == 0;
  my ( $app, $tree ) = fork_for();
  $tree->child('A-Old.txt')->spew_raw("Old\n");
  $tree->child('ro.txt')->spew_raw("Old\n");
  $tree->child('ro.txt')->chmod(0444);
  eval { $app->collect_changes };
  like( $@, qr/ro\.txt can not be rewritten in place, it is not writable/, 'a read-only file to rewrite is refused in the plan' );
  is( $tree->child('ro.txt')->slurp_raw, "Old\n", 'and left alone' );
  ok( $tree->child('A-Old.txt')->exists, 'so is the rest of the tree' );
}

{
  my ( $app, $tree ) = fork_for( class => 'My::FailingWrite' );
  $tree->child('keep.txt')->spew_raw("Old content\n");
  eval { $app->apply_changes };
  my $error = $@;
  like( $error, qr/could not rewrite \S*keep\.txt: disk full/, 'a failed write croaks with the cause' );
  is( $tree->child('keep.txt')->slurp_raw, "Old content\n", 'the original content is restored' );
  my ($backup) = grep { $_->basename =~ /^\.codefork-/ } $tree->children;
  ok( $backup, 'the backup is kept' );
  like( $error, qr/\Q$backup\E/, 'and named in the error' ) if $backup;
  is( $backup->slurp_raw, "Old content\n", 'it holds the original content' ) if $backup;
}

done_testing;
