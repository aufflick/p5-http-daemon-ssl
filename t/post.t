use Test::More;

use HTTP::Daemon::SSL;
use FindBin;
use strict;
use warnings;

use vars qw/$SSL_SERVER_PORT $SSL_SERVER_ADDR/;

eval "use Test::WWW::Mechanize;";
plan skip_all => "Test::WWW::Mechanize required for POST test" if $@;

eval "use Test::Builder;";
plan skip_all => "Test::Builder based Test::More version required for POST test" if $@;

require $FindBin::Bin . "/ssl_settings.req";

plan tests => 19;

my $data66k = do { local $/; open my $f, $FindBin::Bin . "/post66k"; <$f> };
my $data67k = do { local $/; open my $f, $FindBin::Bin . "/post67k"; <$f> };
my $data500k = do { local $/; open my $f, $FindBin::Bin . "/post500k"; <$f> };

my $server = new HTTP::Daemon::SSL(
				   LocalAddr => $SSL_SERVER_ADDR,
				   Listen => 5,
				   Timeout => 30,
				   ReuseAddr => 1,
				   SSL_verify_mode => 0x00,
				   SSL_ca_file => "certs/test-ca.pem",
				   SSL_cert_file => "certs/server-cert.pem");

ok($server, "made test server");

$SSL_SERVER_PORT = $server->sockport;
ok($SSL_SERVER_PORT, "server init port=$SSL_SERVER_PORT");

ok(fileno($server), "server fileno");

unless (fork) {
    close($server);

    # want to fast forward test numbers in the child
    my $builder = Test::More->builder;
    $builder->current_test( $builder->current_test + 13 );

    my $mech = Test::WWW::Mechanize->new();

    $mech->post_ok(
        "https://$SSL_SERVER_ADDR:$SSL_SERVER_PORT/",
        { data => 'foo' },
        "posted small request",
       );

        
        $mech->post_ok(
        "https://$SSL_SERVER_ADDR:$SSL_SERVER_PORT/",
        { data => $data66k },
        "posted 66k request",
       );

    $mech->post_ok(
        "https://$SSL_SERVER_ADDR:$SSL_SERVER_PORT/",
        { data => $data67k },
        "posted 67k request",
       );
    
    $mech->post_ok(
        "https://$SSL_SERVER_ADDR:$SSL_SERVER_PORT/",
        { data => $data500k },
        "posted 500k request",
       );

        
    exit(0);
}

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
    ok(($conn = $server->accept), "accepted third 500k post");
    ok(($r = $conn->get_request), "got request object");
    is($r->method, 'POST', "method is POST");
    
    $conn->send_response("bar");
    close $conn;


wait;

# count child tests
my $builder = Test::More->builder;
$builder->current_test( $builder->current_test + 3 );
