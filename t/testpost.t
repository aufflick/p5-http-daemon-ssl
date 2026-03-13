use Test::More;

use HTTP::Daemon::SSL;
use FindBin;
use strict;
use warnings;

use vars qw/$SSL_SERVER_PORT $SSL_SERVER_ADDR/;

eval "use WWW::Mechanize;";
plan skip_all => "WWW::Mechanize required for POST test" if $@;

eval "use Test::Builder;";
plan skip_all => "Test::Builder based Test::More version required for POST test" if $@;

eval "use LWP::Protocol::https;";
plan skip_all => "LWP::Protocol::https required for POST test" if $@;

require $FindBin::Bin . "/ssl_settings.req";

plan tests => 20;

my $data66k  = do { local $/; open my $f, $FindBin::Bin . "/post66k";  <$f> };
my $data67k  = do { local $/; open my $f, $FindBin::Bin . "/post67k";  <$f> };
my $data500k = do { local $/; open my $f, $FindBin::Bin . "/post500k"; <$f> };

my $server = new HTTP::Daemon::SSL(
    LocalAddr    => $SSL_SERVER_ADDR,
    Listen       => 5,
    Timeout      => 30,
    ReuseAddr    => 1,
    SSL_verify_mode => 0x00,
    SSL_ca_file  => "certs/test-ca.pem",
    SSL_key_file => "certs/server-key.pem",
    SSL_cert_file => "certs/server-cert.pem");

ok($server, "made test server");

$SSL_SERVER_PORT = $server->sockport;
ok($SSL_SERVER_PORT, "server init port=$SSL_SERVER_PORT");

ok(fileno($server), "server fileno");

# Use a pipe so the child can send results to the parent.
# This avoids interleaved TAP output from two processes.
my ($pipe_read, $pipe_write);
pipe($pipe_read, $pipe_write);

unless (fork) {
    close($server);
    close($pipe_read);

    # Use WWW::Mechanize (not the Test:: variant) so that no TAP output
    # is produced in the child process.
    my $mech = WWW::Mechanize->new(
        ssl_opts => {
            verify_hostname => 0,
            SSL_verify_mode => 0x00,
            SSL_ca_file     => $FindBin::Bin . "/../certs/test-ca.pem",
        }
    );

    my @results;

    $mech->post(
        "https://$SSL_SERVER_ADDR:$SSL_SERVER_PORT/",
        { data => 'foo' });
    push @results, $mech->success ? 1 : 0;

    $mech->post(
        "https://$SSL_SERVER_ADDR:$SSL_SERVER_PORT/",
        { data => $data66k });
    push @results, $mech->success ? 1 : 0;

    $mech->post(
        "https://$SSL_SERVER_ADDR:$SSL_SERVER_PORT/",
        { data => $data67k });
    push @results, $mech->success ? 1 : 0;

    $mech->post(
        "https://$SSL_SERVER_ADDR:$SSL_SERVER_PORT/",
        { data => $data500k });
    push @results, $mech->success ? 1 : 0;

    print $pipe_write join(",", @results) . "\n";
    close($pipe_write);
    exit(0);
}

close($pipe_write);

# sink first request
my $conn;
ok(($conn = $server->accept), "accepted first post");
my $r;
ok(($r = $conn->get_request), "got request object");
is($r->method, 'POST', "method is POST");
is($r->content, 'data=foo', 'content matches');
$conn->send_response("bar");
close $conn;

# sink second request
ok(($conn = $server->accept), "accepted second 66k post");
ok(($r = $conn->get_request), "got request object");
is($r->method, 'POST', "method is POST");
$conn->send_response("bar");
close $conn;

# sink third request
ok(($conn = $server->accept), "accepted third 67k post");
ok(($r = $conn->get_request), "got request object");
is($r->method, 'POST', "method is POST");
$conn->send_response("bar");
close $conn;

# sink fourth request
ok(($conn = $server->accept), "accepted fourth 500k post");
ok(($r = $conn->get_request), "got request object");
is($r->method, 'POST', "method is POST");
$conn->send_response("bar");
close $conn;

wait;

# Read child results from pipe and output them as tests (17-20).
# Done after wait() so test numbers appear sequentially.
my $child_results = <$pipe_read>;
chomp $child_results;
my @child_ok = split /,/, $child_results;

ok($child_ok[0], "posted small request");
ok($child_ok[1], "posted 66k request");
ok($child_ok[2], "posted 67k request");
ok($child_ok[3], "posted 500k request");
