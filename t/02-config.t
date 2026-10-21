#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use Path::Tiny;
use App::codefork;

my @keep;    # the temp dirs live as long as the test

sub app_for {
  my ( $config, %files ) = @_;
  my $tree = Path::Tiny->tempdir;
  $tree->child($_)->spew_raw( $files{$_} ) for keys %files;
  my $confdir = Path::Tiny->tempdir;
  $confdir->child('fork.conf')->spew_raw($config);
  push @keep, $tree, $confdir;
  return App::codefork->new(
    config => $confdir->child('fork.conf')->stringify,
    dir    => $tree->stringify,
  );
}

is_deeply(
  app_for("a|b\n\n# no separator\nplain\nc%d\nx|y|z\np%q|r\n")->mods,
  [
    [ replace => 'a',   'b' ],
    [ word    => 'c',   'd' ],
    [ replace => 'x',   'y|z' ],
    [ replace => 'p%q', 'r' ],
  ],
  'one rule per line: empty and separator-less lines ignored, split at the first separator, | wins over %',
);

is_deeply(
  app_for("Foo|Bar\r\nBar|Baz\r\n")->mods,
  [ [ replace => 'Foo', 'Bar' ], [ replace => 'Bar', 'Baz' ] ],
  'CRLF line ends are not part of a rule',
);

{
  my $changes = app_for( "a|b|c\n", 'x.txt' => 'a' )->collect_changes;
  is( $changes->[0]{new_content}, 'b|c', 'the text after the first separator is the replacement' );
}

{
  my ( $change ) = @{ app_for( "Foo|Bar\nBar|Baz\n", 'Foo.txt' => 'Foo' )->collect_changes };
  is( $change->{new_path}, 'Baz.txt', 'the name takes every replace rule, each on the output of the one before' );
  is( $change->{new_content}, 'Baz', 'the content does the same' );
}

{
  my ( $change ) = @{ app_for( "Bar|Baz\nFoo|Bar\n", 'Foo.txt' => 'Foo' )->collect_changes };
  is( $change->{new_path}, 'Bar.txt', 'a rule never sees the output of a rule below it' );
  is( $change->{new_content}, 'Bar', 'in the content neither' );
}

done_testing;
