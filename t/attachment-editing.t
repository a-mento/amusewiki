#!/usr/bin/env perl

use strict;
use warnings;
use utf8;
use Cwd;
use File::Spec::Functions qw/catfile catdir/;
use Test::More tests => 19;
BEGIN {
    $ENV{DBIX_CONFIG_DIR} = "t";
    $ENV{AMW_NO_404_FALLBACK} = 1;
};

use lib catdir(qw/t lib/);
use AmuseWiki::Tests qw/create_site/;
use AmuseWikiFarm::Utils::Amuse qw/from_json/;
use Data::Dumper;
use Test::WWW::Mechanize::Catalyst;
use AmuseWikiFarm::Schema;

my $schema = AmuseWikiFarm::Schema->connect('amuse');

my $site = create_site($schema, '0gall0');
$site->update({ secure_site => 0, epub => 1 });
my $mech = Test::WWW::Mechanize::Catalyst->new(catalyst_app => 'AmuseWikiFarm',
                                               host => $site->canonical);

my $attachment;
{
    my ($rev) = $site->create_new_text({ title => 'HELLO',
                                         textbody => '<p>ciao</p>',
                                       }, 'text');
    my $pdf = catfile(qw/t files shot.pdf/);
    my $got = $rev->add_attachment($pdf);
    for my $i (1..2) {
        $rev->add_attachment($pdf);
    }
    ok $got->{attachment};
    $rev->edit("#ATTACH $got->{attachment}\n" . $rev->muse_body);
    $rev->commit_version;
    $rev->publish_text;
    my $title = $rev->title->discard_changes;
    $mech->get_ok($title->full_uri);
    $attachment = $got->{attachment};
}

$mech->get_ok('/');
$mech->get('/attachments/list');
is $mech->status, 401;
ok $mech->submit_form(with_fields => {__auth_user => 'root', __auth_pass => 'root' }) or die;
$mech->get_ok('/attachments/list');
$mech->content_contains($attachment);
ok $mech->follow_link(url_regex => qr/attachments.*edit/);
ok ($mech->submit_form(with_fields => {
                                       desc_muse => "Hello *there*,\nthis is my **description**",
                                       title_muse => 'Hello *there*',
                                       alt_text => "The alt text",
                                      },
                       button => 'update',
                      ), "Form submitted ok");

$mech->content_contains("Hello <em>there</em>");
$mech->content_contains("this is my <strong>description</strong>");
$mech->get_ok('/attachments/list');
$mech->content_contains("Hello <em>there</em>");
$mech->content_contains("this is my <strong>description</strong>");

$mech->get_ok('/api/attachment/' . $attachment);
{
    my $data = from_json($mech->content);
    is $data->{alt_text}, "The alt text";
    ok !$data->{error};
}
$mech->get_ok('/api/attachment/garbage');
{
    my $data = from_json($mech->content);
    ok $data->{error};
}



