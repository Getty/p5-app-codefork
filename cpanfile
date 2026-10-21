requires 'Moo';
requires 'Path::Tiny';
requires 'Text::Diff';

on test => sub {
  requires 'Test::More', '0.96';
};
