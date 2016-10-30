package DockerCommand;
use strict;
use warnings;
use Path::Tiny;
use AnyEvent::FileLock;
use Promise;
use Promised::Flow;
use Promised::Command;

my $LockPath = path (__FILE__)->parent->parent->child ('local/docker.lock');

sub run ($$$) {
  my ($class, $def, $out) = @_;

  my $image = $def->{image};
  my $name = 'cennel-' . $def->{name};
  $name =~ s{/}{-}g;
  $name =~ s/[^A-Za-z0-9_-]/_/g;

  my $lock_w;
  my $wait_lock = Promise->new (sub {
    my ($ok, $ng) = @_;
    $lock_w = AnyEvent::FileLock->flock
        (file => $LockPath->stringify,
         mode => '>',
         timeout => 60*20,
         cb => sub {
           my $file = $_[0];
           if (defined $file) {
             $ok->($file);
           } else {
             $ng->($!);
           }
           undef $lock_w;
         });
  });

  my $ipaddr;
  my $lock;
  return promised_cleanup {
    undef $lock;
    undef $lock_w;
  } Promise->resolve->then (sub {
    my $pull = Promised::Command->new (['docker', 'pull', $image]);
    $pull->stdout ($out);
    $pull->stderr ($out);
    $pull->timeout (60*5);
    $out->("\$ docker pull $image");
    return $pull->run->then (sub { return $pull->wait });
  })->then (sub {
    die $_[0] unless $_[0]->exit_code == 0;
    return $wait_lock;
  })->then (sub {
    $lock = $_[0];
    my $kill = Promised::Command->new (['docker', 'kill', $name]);
    $kill->stdout ($out);
    $kill->stderr ($out);
    $kill->timeout (60*5);
    $out->("\$ docker kill $name");
    return $kill->run->then (sub { return $kill->wait });
  })->then (sub {
    #die $_[0] unless $_[0]->exit_code == 0;
    my $rm = Promised::Command->new (['docker', 'rm', $name]);
    $rm->stdout ($out);
    $rm->stderr ($out);
    $rm->timeout (60*5);
    $out->("\$ docker rm $name");
    return $rm->run->then (sub { return $rm->wait });
  })->then (sub {
    #die $_[0] unless $_[0]->exit_code == 0;
    my $addr = Promised::Command->new
        (['sh', '-c', q{ip route | awk '/docker0/ { print $NF }'}]);
    $addr->stdout (\my $ip);
    $addr->stderr ($out);
    $addr->timeout (60);
    $out->("\$ ip route");
    return $addr->run->then (sub { return $addr->wait })->then (sub {
      die $_[0] unless $_[0]->exit_code == 0;
      die "|$ip| is not an IP address" unless $ip =~ /^([0-9.]+)$/;
      $ipaddr = $1;
    });
  })->then (sub {
    my $run = Promised::Command->new ([
      'docker', 'run',
      '-d',
      '--name=' . $name,
      '--restart=always',
      '--add-host=dockerhost:' . $ipaddr,
      @{$def->{options} or []},
      $image,
      @{$def->{command} or []},
    ]);
    $run->stdout ($out);
    $run->stderr ($out);
    $run->timeout (60*15);
    $out->("\$ docker run ... $image ...");
    return $run->run->then (sub { return $run->wait });
  })->then (sub {
    die $_[0] unless $_[0]->exit_code == 0;
  });
} # run

1;

=head1 LICENSE

Copyright 2016 Wakaba <wakaba@suikawiki.org>.

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU Affero General Public License as
published by the Free Software Foundation, either version 3 of the
License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but
WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
Affero General Public License for more details.

You does not have received a copy of the GNU Affero General Public
License along with this program, see <http://www.gnu.org/licenses/>.

=cut
