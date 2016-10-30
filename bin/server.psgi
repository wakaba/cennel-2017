# -*- Perl -*-
use strict;
use warnings;
use Path::Tiny;
use JSON::PS;
use Wanage::HTTP;
use Warabe::App;
use Web::URL;
use Web::Transport::ConnectionClient;
use DockerCommand;

my $defs_path = path ($ENV{CENNEL_DEFS_FILE} // die "No |CENNEL_DEFS_FILE|");

return sub {
  my $http = Wanage::HTTP->new_from_psgi_env ($_[0]);
  my $app = Warabe::App->new_from_http ($http);
  
  return $http->send_response (onready => sub () {
    $app->execute (sub () {
      my $path = $app->path_segments;

      if (@$path == 1 and $path->[0] eq 'hook') {
        $app->requires_request_method ({POST => 1});
        $app->requires_same_origin
            if not $app->http->request_method_is_safe and
               defined $app->http->get_request_header ('Origin');

        my $name = $app->text_param ('name') // '';
        return $app->throw_error (400, reason_phrase => 'Bad |name|')
            unless length $name;

        my $Defs = json_bytes2perl $defs_path->slurp;

        my $def = $Defs->{containers}->{$name};
        return $app->throw_error (404, reason_phrase => 'Unknown |name|')
            unless defined $def;

        my $IkachanURL = Web::URL->parse_string ($Defs->{ikachan_url});
        my $ika_client = defined $IkachanURL
            ? Web::Transport::ConnectionClient->new_from_url ($IkachanURL)
            : undef;
        my $ika = sub {
          my ($is_privmsg, $msg) = @_;
          if (defined $ika_client) {
            $ika_client->request
                (path => [$is_privmsg ? 'privmsg' : 'notice'],
                 method => 'POST',
                 params => {
                   channel => $Defs->{ikachan_channel},
                   message => "Cennel: $msg",
                 });
          } else {
            warn "$msg\n";
          }
        };

        $app->http->set_response_header
            ('Content-Type' => 'text/plain; charset=utf-8');
        return DockerCommand->run (
          $def,
          sub {
            return unless defined $_[0];
            $app->http->send_response_body_as_ref (\q{.});
            $ika->(0, $_[0]);
          },
        )->catch (sub {
          $app->http->send_response_body_as_ref (\qq{\x0AFailed});
          $ika->(1, $_[0]);
        })->then (sub {
          $app->http->close_response_body;
          return $ika_client->close if defined $ika_client;
        });
      }

      if (@$path == 1 and $path->[0] eq 'robots.txt') {
        return $app->send_plain_text ("User-agent: *\x0ADisallow: /");
      }

      return $app->send_error (404);
    });
  });
};

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
