#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use Path::Tiny;
use App::codefork;

my @keep;    # the temp dirs live as long as the test

sub content_after {
  my ( $rules, $content ) = @_;
  my $tree = Path::Tiny->tempdir;
  $tree->child('file.txt')->spew_raw($content);
  my $confdir = Path::Tiny->tempdir;
  $confdir->child('fork.conf')->spew_raw( join( "\n", @$rules )."\n" );
  push @keep, $tree, $confdir;
  my $app = App::codefork->new(
    config => $confdir->child('fork.conf')->stringify,
    dir    => $tree->stringify,
  );
  my ( $change ) = @{ $app->collect_changes };
  return $change ? $change->{new_content} : $content;
}

is(
  content_after( ['hh%ah'], "hh = 1;\nmy hh,hh\nend hh" ),
  "ah = 1;\nmy ah,ah\nend ah",
  'start of text, adjacent words and end of text are replaced',
);
is( content_after( ['hh%ah'], 'ohhh hhx xhh hh' ), 'ohhh hhx xhh ah', 'never inside a longer word' );
is( content_after( ['hh%ah'], 'hh' ), 'ah', 'the whole text as the word' );
is( content_after( ['h+%ah'], 'hhh hx' ), 'ah hx', 'from stays regex source' );
is( content_after( ['hh%ah'], 'hh_x' ), 'ah_x', 'the underscore is a boundary, as documented' );

my $tree = Path::Tiny->tempdir;
$tree->child('hh.txt')->spew_raw('x');
my $confdir = Path::Tiny->tempdir;
$confdir->child('fork.conf')->spew_raw("hh%ah\n");
my $changes = App::codefork->new(
  config => $confdir->child('fork.conf')->stringify,
  dir    => $tree->stringify,
)->collect_changes;
is_deeply( $changes, [], 'the word rule never renames' );

done_testing;
