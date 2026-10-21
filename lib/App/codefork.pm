package App::codefork;
# ABSTRACT: Worlds dumbest code forker
our $VERSION = '1.001';
use Moo;
use Carp qw( croak );
use Path::Tiny;
use Text::Diff;

has config => (
  is => 'ro',
  required => 1,
  coerce => sub { path($_[0]) },
);

has dir => (
  is => 'ro',
  default => sub { path('.')->absolute },
  coerce => sub { path($_[0])->absolute },
);

has debug => (
  is => 'ro',
  default => sub { $ENV{CODEFORK_DEBUG} ? 1 : 0 },
);

has mods => (
  is => 'lazy',
);

has _config_realpath => (
  is       => 'lazy',
  init_arg => undef,
);

=attr config

Path to the config file containing forking instructions. Required. When the
config file lies inside L</dir>, it is left out of the walk: it is neither
rewritten nor renamed.

=attr dir

Work directory to process. Defaults to current directory.

=attr debug

Show debug information. Enabled via C<CODEFORK_DEBUG=1> environment variable.

=attr mods

Parsed modification instructions from the config file.

=cut

sub _build_mods {
  my ($self) = @_;
  my @lines = $self->config->lines({ chomp => 1 });
  return [ map {
    if (/\|/) {
      [ replace => split(/\|/, $_, 2) ]
    } elsif (/%/) {
      [ word => split(/%/, $_, 2) ]
    } else {
      ()
    }
  } @lines ];
}

sub _build__config_realpath { shift->config->realpath->stringify }

sub collect_changes {
  my ($self) = @_;
  $self->log('Parsing config...');
  $self->log($_->[0].': '.$_->[1].' => '.$_->[2]) for @{$self->mods};
  my @changes;
  $self->_collect_dir($self->dir, '', \@changes);
  $self->_check_changes(\@changes);
  return \@changes;
}

=method collect_changes

    my $changes = $app->collect_changes;

Recursively scans the work directory and computes all modifications without
applying them. Returns an arrayref of change hashrefs with keys C<old_path>,
C<new_path>, C<old_content>, C<new_content>. Only files are changes, with one
exception: an empty directory whose path changes is a change with empty content
on both sides, so it is renamed like a file and shows in the diff as a rename.

Croaks, before anything is written, when the plan would lose a file or could
not be applied: a new path that already exists and is not itself renamed away,
a new path that two changes share, a new path below an existing file that is
not renamed away or below another change's new path, renames that form a
cycle, or a file whose content changes but which is not writable.

=cut

sub _check_changes {
  my ( $self, $changes ) = @_;
  my ( %target, %vacated, @problems );
  for my $change (@$changes) {
    next if $change->{old_path} eq $change->{new_path};
    push @{ $target{ $change->{new_path} } }, $change->{old_path};
    $vacated{ $change->{old_path} } = 1;
  }
  for my $new_path ( sort keys %target ) {
    my @from = @{ $target{$new_path} };
    if ( @from > 1 ) {
      push @problems, join( ' and ', @from ).' would all become '.$new_path;
    } elsif ( !$vacated{$new_path} && $self->dir->child($new_path)->exists ) {
      push @problems, $new_path.' (from '.$from[0].') already exists';
    }
    for my $parent ( $self->_parents($new_path) ) {
      my $on_disk = $self->dir->child($parent);
      my $blocker = $target{$parent} ? 'the new path of '.$target{$parent}[0]
        : !$vacated{$parent} && -e $on_disk && !-d $on_disk ? 'an existing file'
        : undef;
      next unless $blocker;
      push @problems, $new_path.' (from '.$from[0].') needs a directory '.$parent.', which is '.$blocker;
      last;
    }
  }
  for my $change ( grep { $_->{old_content} ne $_->{new_content} } @$changes ) {
    push @problems, $change->{old_path}.' can not be rewritten in place, it is not writable'
      unless -w $self->dir->child( $change->{old_path} );
  }
  croak __PACKAGE__.' refuses the plan, nothing was written:'."\n"
    .join( "\n", map { '  '.$_ } @problems ) if @problems;
  return $self->_apply_order($changes);
}

sub _apply_order {
  my ( $self, $changes ) = @_;
  my @pending = @$changes;
  my @order;
  while (@pending) {
    my %occupied = map { $_->{old_path} => 1 }
      grep { $_->{old_path} ne $_->{new_path} } @pending;
    my ( @ready, @blocked );
    for my $change (@pending) {
      my $waits = grep { $occupied{$_} } $change->{new_path}, $self->_parents( $change->{new_path} );
      push @{ $waits ? \@blocked : \@ready }, $change;
    }
    croak __PACKAGE__.' refuses a cycle of renames, nothing was written: '
      .join( ', ', map { $_->{old_path}.' -> '.$_->{new_path} } @blocked ) unless @ready;
    push @order, @ready;
    @pending = @blocked;
  }
  return \@order;
}

sub _parents {
  my ( $self, $rel ) = @_;
  my @parents;
  for ( my $parent = path($rel)->parent; $parent->stringify ne '.'; $parent = $parent->parent ) {
    push @parents, $parent->stringify;
  }
  return @parents;
}

sub _collect_dir {
  my ($self, $dir, $new_dir_prefix, $changes) = @_;
  my @mods = @{$self->mods};

  for my $entry (sort $dir->children) {
    my $basename = $entry->basename;
    next if $basename eq '.git' || $basename eq '.svn';
    next if $entry->is_file && $entry->realpath->stringify eq $self->_config_realpath;

    my $new_basename = $basename;
    for my $mod (@mods) {
      if ($mod->[0] eq 'replace') {
        $new_basename =~ s/$mod->[1]/$mod->[2]/g;
      }
    }

    my $old_rel = $entry->relative($self->dir)->stringify;
    my $new_rel = length($new_dir_prefix)
      ? "$new_dir_prefix/$new_basename"
      : $new_basename;

    if ($entry->is_dir) {
      push @$changes, {
        old_path    => $old_rel,
        new_path    => $new_rel,
        old_content => '',
        new_content => '',
      } if $new_rel ne $old_rel && !$entry->children;
      $self->_collect_dir($entry, $new_rel, $changes);
    } else {
      my $content = $entry->slurp_raw;
      my $new_content = $content;
      for my $mod (@mods) {
        my ($cmd, $from, $to) = @$mod;
        if ($cmd eq 'replace') {
          $new_content =~ s/$from/$to/g;
        } elsif ($cmd eq 'word') {
          $new_content =~ s/(?<![A-Za-z0-9])$from(?![A-Za-z0-9])/$to/g;
        }
      }

      if ($new_rel ne $old_rel || $new_content ne $content) {
        push @$changes, {
          old_path => $old_rel,
          new_path => $new_rel,
          old_content => $content,
          new_content => $new_content,
        };
      }
    }
  }
}

sub generate_diff {
  my ($self, $changes) = @_;
  $changes //= $self->collect_changes;
  my $output = '';
  for my $change (@$changes) {
    my $renamed = $change->{old_path} ne $change->{new_path};
    my $modified = $change->{old_content} ne $change->{new_content};

    if ($modified) {
      my $diff_text = diff(
        \$change->{old_content},
        \$change->{new_content},
        {
          STYLE => 'Unified',
          FILENAME_A => "a/$change->{old_path}",
          FILENAME_B => "b/$change->{new_path}",
        },
      );
      if ($renamed) {
        my $header = "rename from $change->{old_path}\nrename to $change->{new_path}\n";
        $diff_text =~ s/^(---\s)/$header$1/m;
      }
      $output .= $diff_text;
    } elsif ($renamed) {
      $output .= "diff $change->{old_path} $change->{new_path}\n";
      $output .= "rename from $change->{old_path}\n";
      $output .= "rename to $change->{new_path}\n";
    }
  }
  return $output;
}

=method generate_diff

    my $diff = $app->generate_diff($changes);

Generates a unified diff string from the collected changes. If C<$changes>
is not passed, calls L</collect_changes> automatically.

=cut

sub apply_changes {
  my ($self, $changes) = @_;
  $changes //= $self->collect_changes;
  my %made;
  for my $change ( @{ $self->_check_changes($changes) } ) {
    my $old = $self->dir->child($change->{old_path});
    my $new = $self->dir->child($change->{new_path});
    my $renamed = $change->{old_path} ne $change->{new_path};
    my $modified = $change->{old_content} ne $change->{new_content};

    $self->_make_parents( $change, \%made ) if $renamed;

    if ($modified) {
      $self->log("modify: $change->{old_path}");
      $self->_write_file( $old, $change->{new_content} );
    }
    if ($renamed) {
      $self->log("rename: $change->{old_path} -> $change->{new_path}");
      $old->move($new);
    }
  }
  $self->_take_dir_attributes( \%made );
  $self->_remove_emptied_dirs($changes);
  return scalar @$changes;
}

sub _write_file {
  my ( $self, $file, $content ) = @_;
  # the new content goes into the existing inode: owner, group, mode, hard
  # links, ACLs and xattrs stay; a 0600 backup covers a write that fails
  my $backup = Path::Tiny->tempfile(
    TEMPLATE => '.codefork-XXXXXXXX',
    DIR      => $file->parent->stringify,
    UNLINK   => 0,
  );
  my $copied = eval { $backup->append_raw( $file->slurp_raw ); 1 };
  unless ($copied) {
    my $error = $@;
    $backup->remove;
    croak __PACKAGE__.'->apply_changes could not back up '.$file.', it is untouched: '.$error;
  }
  my $written = eval { $self->_overwrite( $file, $content ); 1 };
  unless ($written) {
    my $error = $@;
    $error =~ s/\s+\z//;
    my $restored = eval { $self->_overwrite( $file, $backup->slurp_raw ); 1 };
    croak __PACKAGE__.'->apply_changes could not rewrite '.$file.': '.$error.'; '
      .( $restored ? 'the original content is restored, a copy stays in ' : 'the original content is in ' )
      .$backup;
  }
  $backup->remove;
  return;
}

sub _overwrite {
  my ( $self, $file, $content ) = @_;
  my $fh = $file->openrw_raw;
  truncate $fh, 0 or croak 'truncate '.$file.': '.$!;
  print {$fh} $content or croak 'write '.$file.': '.$!;
  close $fh or croak 'close '.$file.': '.$!;
  return;
}

sub _make_parents {
  my ( $self, $change, $made ) = @_;
  my @new = reverse $self->_parents( $change->{new_path} );
  my @old = reverse $self->_parents( $change->{old_path} );
  for my $i ( 0 .. $#new ) {
    my $dir = $self->dir->child( $new[$i] );
    next if -d $dir;
    $dir->mkpath;
    # the directory it replaces, when the depth tells which one that is
    $made->{ $new[$i] } = @old == @new ? $self->dir->child( $old[$i] )->stat : undef;
  }
  return;
}

sub _take_dir_attributes {
  my ( $self, $made ) = @_;
  for my $rel ( sort { ( $b =~ tr{/}{} ) <=> ( $a =~ tr{/}{} ) || $a cmp $b } keys %$made ) {
    my $stat = $made->{$rel} or next;
    my $dir  = $self->dir->child($rel)->stringify;
    chown $stat->uid, $stat->gid, $dir or chown -1, $stat->gid, $dir;    # as far as permitted
    chmod $stat->mode & 07777, $dir or croak __PACKAGE__.'->apply_changes can not chmod '.$rel.': '.$!;
  }
  return;
}

sub _remove_emptied_dirs {
  my ( $self, $changes ) = @_;
  my %dirs;
  for my $change ( grep { $_->{old_path} ne $_->{new_path} } @$changes ) {
    $dirs{$_} = 1 for $self->_parents( $change->{old_path} );
  }
  for my $rel ( sort { ( $b =~ tr{/}{} ) <=> ( $a =~ tr{/}{} ) || $a cmp $b } keys %dirs ) {
    my $dir = $self->dir->child($rel);
    next unless $dir->is_dir && !$dir->children;
    $self->log('remove: '.$rel);
    rmdir $dir or croak __PACKAGE__.'->apply_changes can not remove '.$rel.': '.$!;
  }
  return;
}

=method apply_changes

    my $count = $app->apply_changes($changes);

Applies the collected changes to disk. Returns the number of changes applied.
The plan is checked again before the first write and refused the same way as
in L</collect_changes>; a file is renamed only after the file or directory in
its way has been renamed away.

A file keeps everything but its content and its name: the new content is
written into the existing file, and a rename moves that file. Owner, group,
mode, hard links, ACLs and extended attributes stay as they were. Before the
write, the old content is copied to a hidden C<.codefork-*> backup next to the
file (mode 0600), which is removed once the write succeeded; when the write
fails, the original content is restored from it and apply croaks naming the
backup. A directory created for a rename takes the mode of the directory it
replaces, and its owner and group as far as permitted. A directory the renames
left empty is removed afterwards, deepest first; a directory that still holds
something stays.

=cut

sub log {
  my ($self, $text) = @_;
  print STDERR $text."\n" if $self->debug;
}

=method log

    $self->log($message);

Prints a log message to STDERR if C<debug> is enabled.

=cut

sub run {
  my ($class, @args) = @_;

  my $command = 'diff';
  my $config = 'fork.conf';
  my $output_file;

  if (@args && $args[0] eq 'apply') {
    $command = 'apply';
    shift @args;
    $config = shift @args if @args;
  } elsif (@args && $args[0] eq 'output') {
    $command = 'output';
    shift @args;
    if (@args == 2) {
      $config = shift @args;
    }
    $output_file = shift @args;
    die "output command requires a filename\n" unless defined $output_file;
  } elsif (@args) {
    $config = shift @args;
  }

  die "Config file '$config' not found\n" unless -f $config;

  my $app = $class->new(config => $config);
  my ( undef, $file, $line ) = caller;
  my $ok = eval { $app->_run_command( $command, $output_file ); 1 };
  return if $ok;
  # a croak of this class points at the caller of run - the CLI shows the message only
  my $error = $@;
  my $at    = ' at '.$file.' line '.$line.".\n";
  $error = substr( $error, 0, -length $at )."\n"
    if length $error > length $at && substr( $error, -length $at ) eq $at;
  die $error;
}

=method run

    App::codefork->run(@ARGV);

CLI entry point. Parses arguments and executes the appropriate command. When
the plan is refused (see L</collect_changes>), it dies with the refusal alone,
without the file and line a croak adds, so the CLI exits non-zero and prints
just the message.

=cut

sub _run_command {
  my ( $self, $command, $output_file ) = @_;
  my $changes = $self->collect_changes;

  if ($command eq 'diff') {
    my $diff = $self->generate_diff($changes);
    if (length $diff) {
      print $diff;
    } else {
      print "No changes.\n";
    }
  } elsif ($command eq 'apply') {
    my $count = $self->apply_changes($changes);
    print "Applied $count change(s).\n";
  } elsif ($command eq 'output') {
    my $diff = $self->generate_diff($changes);
    path($output_file)->spew_raw($diff);
    print "Wrote diff to $output_file\n";
  }
}

=encoding utf8

=head1 SYNOPSIS

    use App::codefork;

    my $app = App::codefork->new(config => 'fork.conf');

    # Collect changes without applying them
    my $changes = $app->collect_changes;

    # Preview as unified diff
    print $app->generate_diff($changes);

    # Apply when ready
    $app->apply_changes($changes);

=head1 DESCRIPTION

App::codefork is a simple tool for forking code by performing systematic
replacements in filenames and file contents across directory trees.

The workflow is diff-based and safe by design: changes are first collected
and can be previewed as a unified diff before anything is modified on disk.

For the command-line interface, see L<codefork>.

=head1 UPGRADE NOTICE

B<Version 1.000 has a completely new command-line interface.>

The old C<--config>, C<--dir>, and C<--debug> flags from L<MooX::Options>
are no longer supported. The new interface uses positional commands instead:

    # Old (no longer works):
    codefork --config fork.conf --dir /path/to/code

    # New:
    cd /path/to/code
    codefork fork.conf

See L<codefork> for the full new command-line syntax.

Debug output is now enabled via the C<CODEFORK_DEBUG=1> environment variable
instead of C<--debug>.

=head1 CONFIG FILE FORMAT

The config file (default: C<fork.conf>) contains replacement instructions,
one per line:

=over 4

=item * C<from|to> - Replace regex pattern C<from> with C<to> in filenames and file contents

=item * C<from%to> - Replace whole word C<from> with C<to> in file contents only. C<from> matches only where no letter or digit (C<A-Z>, C<a-z>, C<0-9>) comes directly before or after it, so C<hh> won't match inside C<ohhh>; the start and the end of a file count as a boundary

=back

Example config:

    HomeHive|AqHive
    homehive|aqhive
    hh%ah

Empty lines and lines without a C<|> or C<%> separator are ignored. The config
file itself is never rewritten or renamed, even when it lies inside the tree.

=head1 ENVIRONMENT

=over 4

=item C<CODEFORK_DEBUG>

Set to a true value to enable verbose debug output to STDERR.

=back

=cut

1;
