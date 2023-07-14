package AmuseWikiFarm::Controller::Root;
use Moose;
with 'AmuseWikiFarm::Role::Controller::HumanLoginScreen';
use namespace::autoclean;
BEGIN { extends 'Catalyst::Controller' }

use AmuseWikiFarm::Utils::Amuse ();
use AmuseWikiFarm::Log::Contextual;
use HTTP::BrowserDetect;
use IO::File;
use Text::Amuse::Utils ();

use constant {
    AMW_NO_404_FALLBACK => $ENV{AMW_NO_404_FALLBACK},
};

#
# Sets the actions in this controller to be registered with no prefix
# so they function identically to actions created in MyApp.pm
#
__PACKAGE__->config(namespace => '');

=encoding utf-8

=head1 NAME

AmuseWikiFarm::Controller::Root - Root Controller for AmuseWikiFarm

=head1 DESCRIPTION

This class provides the site selection and the theme management.

=head1 METHODS

Values always stashed for every action:

=over 4

=item site

The master L<AmuseWikiFarm::Schema::Result::Site> object. If the site
is not looked up correctly, a 404 is issued. At some point a special
page must be provided.

=item user_login_uri

The URI for the user login

=item current_locale_code

Locale code

=item current_locale_name

Locale name

=item navigation

(Present only if there are related sites or special pages).

=back

=cut

sub check_unicode_errors :Chained('/') :PathPart('') :CaptureArgs(0) {
    my ($self, $c) = @_;
    if ($c->stash->{BAD_UNICODE_DATA}) {
        $c->detach('/bad_request');
    }
}

sub site_no_auth :Chained('check_unicode_errors') :PathPart('') :CaptureArgs(0) {
    my ($self, $c) = @_;
    my $req = $c->request;
    # Dlog_debug { "Request $_" } $req;
    log_debug { "Starting request " . $req->uri->as_string . " from IP " . $req->address };

    $c->stash(amw_user_agent => HTTP::BrowserDetect->new($req->user_agent || ''));

    # catch the host. ->uri is an URI object, as per doc.
    my $host = $req->uri->host;

    # lookup in the db: first the canonical, then the vhosts
    my $site = $c->model('DB::Site')->find({ canonical => $host });
    unless ($site) {
        if (my $vhost = $c->model('DB::Vhost')->find($host)) {
            $site = $vhost->site;

            unless ($site->allow_hostname_aliases) {
                # permit the access to the site only if it's the canonical
                # one this is kind of questionable, but it's a common SEO
                # strategy to avoid splitting the results.
                my $uri = $req->uri->clone;
                $uri->host($site->canonical);

                # in case there is a session active, avoid crash
                $c->stash(site => $site);

                # log_debug { "Redirecting to " . $uri->as_string };
                # place a permanent redirect
                $c->response->redirect($uri->as_string, 301);
                $c->detach();
                return;
            }
        }
        else {
            log_info { "$host not found in vhosts" };
        }
    }
    unless ($site) {
        $c->detach('/not_permitted');
        return;
    }
    # stash the site object, this is needed for session operations
    $c->stash(site => $site);
    my $site_id = $site->id;
    log_debug { "Site ID for $host is $site_id, with locale " . $site->locale };
    log_debug { "session id is " . ($c->sessionid || '<none>') };


    # this means some fucker reused a cookie from another site to gain
    # access to this. A bit unlikely, but better now than later. So,
    # assert that the session belongs to the same site This is very
    # common with some vintage browser (IE, anyone) and some crappy
    # robots.
    if ($c->sessionid) {
        my $session_site_id = $c->session->{site_id} || '';
        if ($session_site_id ne $site_id) {
            Dlog_info {
                "Session mismatch, <$session_site_id> ne <$site_id>".
                  " deleting session, requesting " . $req->uri . " " . $_
              } ($c->session);
            $c->delete_session;
            die "This shouldn't happen" if $c->user_exists;
            # a this point, this is a bug
        }
    }

    log_debug { "User exists? " .  $c->user_exists };
    $c->stash(blog_style => $site->blog_style);

    # force ssl for authenticated users
    $self->redirect_to_secure($c) if $c->user_exists;

    my $locale = $site->locale || 'en';
    # in case something weird happened
    unless ($site->known_langs->{$locale}) {
        log_error { "$locale is not recognized on $site_id " . $req->path };
        $locale = 'en';
    }

    if (my $set_language = $req->query_params->{__language}) {
        $set_language .= ''; # force stringification. probably not needed.
        if ($site->known_langs->{$set_language}) {
            $c->session(user_locale => $set_language,
                        site_id => $site->id,
                       );
        }
    }
    if (my $switch_theme = $req->query_params->{__switch_theme}) {
        my $use_alternate = !$c->session->{use_alternate_theme};
        $c->session(use_alternate_theme => $use_alternate,
                    site_id => $site->id,
                   );
    }

        if ($c->sessionid) {
            if (my $user_locale = $c->session->{user_locale}) {
                if (my $language = $site->known_langs->{$user_locale}) {
                    log_debug { "User language is $language" };
                    # validated by now
                    $locale = $user_locale;
                }
            }
            if ($c->session->{use_alternate_theme}) {
                $c->stash(use_alternate_theme => 1);
            }
        }

    $c->stash(current_locale_code => $locale,
              current_locale_name => $site->known_langs->{$locale},
             );
    if (Text::Amuse::Utils::lang_code_is_rtl($locale)) {
        $c->stash(locale_is_rtl => 1);
    }
    # set the localization
    $c->set_language($locale, $site_id);

    # set no-cache by default, previously in the middleware
    $c->response->header('Cache-Control' => 'no-cache');
    return 1;
}

sub site :Chained('site_no_auth') :PathPart('') :CaptureArgs(0) {
    my ($self, $c) = @_;
    my $site = $c->stash->{site};
    if ($site->is_private) {
        if ($self->ip_is_whitelisted($c)) {
            return 1;
        }
        else {
            $self->check_login($c);
        }
    }
}

sub site_robot_index :Chained('site') :PathPart('') :CaptureArgs(0) {
    my ($self, $c) = @_;
    $c->stash(please_index => 1);
}

sub site_user_required :Chained('site') :PathPart('') :CaptureArgs(0) {
    my ($self, $c) = @_;
    $self->check_login($c);
}

sub site_human_required :Chained('site') :PathPart('') :CaptureArgs(0) {
    my ($self, $c) = @_;
    $self->check_human($c);
}

sub bad_request :Private {
    my ($self, $c) = @_;
    $c->response->content_type('text/plain');
    $c->response->body('Bad Unicode data');
    $c->response->status(400);
}

sub not_found :Private {
    my ($self, $c) = @_;
    $c->stash(please_index => 0);
    log_debug { "In the not_found!" };
    # last chance: look into the redirections if we have a type and an uri,
    # set in C::Library or C::Category
    if (my $site = $c->stash->{site}) {
        if (my $f_class = $c->stash->{f_class}) {
            if (my $uri = $c->stash->{uri}) {
                if (my $red = $site->redirections->find({
                                                         type => $f_class,
                                                         uri => $uri
                                                        })) {
                    $c->response->redirect($c->uri_for($red->full_dest_uri), 301);
                    $c->detach();
                    return;
                }
            }
        }
        if (my $replacement = $c->stash->{site}->legacy_links
            ->find({ legacy_path => $c->request->uri->path_query })) {
            my $new_path = $replacement->new_path;
            $c->response->redirect($c->uri_for($new_path), 301);
            $c->detach();
            return;
        }
        # if looks like an image, handle it.
        if (AMW_NO_404_FALLBACK) {
            log_debug { "Not falling back on 404" };
        }
        elsif ($c->request->path =~ m/([0-9a-z-]+\.(jpe?g|png|pdf))\z/) {
            my $name = $1;
            if (my $att = $site->attachments->by_uri($name)) {
                $c->stash(serve_static_file => $att->f_full_path_name);
                $c->detach($c->view('StaticFile'));
            }
            else {
                $c->response->status(404);
                my $replacement = $c->path_to(qw/root static images not-found.png/)->stringify;
                if (-f $replacement) {
                    my $fh = IO::File->new($replacement, 'r');
                    $c->response->headers->content_type('image/png');
                    $c->response->header('Cache-Control' => 'no-cache, no-store, must-revalidate');
                    $c->response->body($fh);
                }
                else {
                    $c->response->body('Not found');
                }
            }
            return;
        }
    }
    $c->response->status(404);
    log_info {
        $c->request->uri
          . " not found by " . ($c->request->user_agent || '')
          . " referred by " . ($c->request->referer || '')
      };
    $c->stash(error_msg => $c->loc("Page not found!"));
    $c->stash(template => "error.tt");
}

sub not_permitted :Private {
    my ($self, $c) = @_;
    $c->response->status(403);
    log_info { "Access denied to " . $c->request->uri };
    $c->response->body("Access denied");
    return;
}

sub gone :Private {
    my ($self, $c) = @_;
    log_info { "Accessed a deleted file: " . $c->request->uri };
    $c->stash(error_msg => $c->loc("Page not found!"));
    $c->stash(template => "error.tt");
    $c->response->status(410);
    return;
}

=head2 random

Path: /random

Get the a random text

=cut

sub random :Chained('/site') :Args(0) {
    my ($self, $c) = @_;
    if (my $text = $c->stash->{site}->titles->random_text) {
        $c->response->redirect($c->uri_for_action('/library/text', [$text->uri]));
    }
    else {
        $c->detach('/not_found');
    }
}

sub rss_xml :Chained('/site') :PathPart('rss.xml') :Args(0) {
    my ($self, $c) = @_;
    $c->detach('/feed/index');
}

sub favicon :Chained('/site_no_auth') :PathPart('favicon.ico') :Args(0) {
    my ($self, $c) = @_;
    $c->detach('/sitefiles/local_files',
                ['favicon.ico']);
}

sub apple_touch_icon :Chained('/site_no_auth') :PathPart('apple-touch-icon.png') :Args(0) {
    my ($self, $c) = @_;
    $c->detach('/sitefiles/local_files',
               ['opengraph.png']);
}

sub robots_txt :Chained('/site_no_auth') :PathPart('robots.txt') :Args(0) {
    my ($self, $c) = @_;
    my $site = $c->stash->{site};
    my $robots;
    if (!$site or $site->is_private) {
        $robots = "User-agent: *\nDisallow: /\n";
    }
    else {
        $robots = $site->robots_txt;
    }
    $c->response->content_type('text/plain');
    $c->response->body($robots);
}

sub sitemap_txt :Chained('/site') :PathPart('sitemap.txt') :Args(0) {
    my ($self, $c) = @_;
    my $site = $c->stash->{site};
    my @urls;
    my $base = $site->canonical_url_secure;
    foreach my $root (qw/opds
                         feed
                         latest
                         listing
                         library
                         search
                        /) {
        push @urls, $base . '/' . $root;
    }
    my $texts = $site->titles->published_all
      ->search(undef, { order_by => [qw/f_class sorting_pos/] })->listing_tokens_plain;
    while (@$texts) {
        my $text = shift @$texts;
        push @urls, $base . $text->{full_uri};
    }
    foreach my $ct ($site->site_category_types->active->with_index_page->ordered->all) {
        push @urls, $base . $ct->full_uri;
        my $categories = $site->categories->by_type($ct->category_type)->with_texts(deferred => $c->user_exists,
                                                                                    sort => 'type')->listing_tokens;
        while (@$categories) {
            my $cat = shift @$categories;
            push @urls, $base . $cat->{full_uri};
        }
    }
    foreach my $f ($site->public_files->search({ file_name => { like => '%.html' } })->all) {
        my $name = $f->file_name;
        $name =~ s/\.html//;
        push @urls, $base . "/p/$name";
    }
    $c->response->content_type('text/plain');
    $c->response->body(join("\n", @urls) . "\n");
}

=head2 index

The root page (/) points to /library/ if there is no special/index

=cut

sub index :Chained('/site') :PathPart('') :Args(0) {
    my ( $self, $c ) = @_;
    # handle legacy paths if there are arguments
    my $path = $c->request->uri->path_query;
    if ($path ne '/') {
        log_debug { "Checking the legacy paths for $path" };
        if (my $replacement = $c->stash->{site}->legacy_links
            ->find({ legacy_path => $path })) {
            my $new_path = $replacement->new_path;
            $c->response->redirect($c->uri_for($new_path), 301);
            $c->detach();
            return;
        }
    }
    # default
    my $target = $c->uri_for_action('/latest/index');
    my $site = $c->stash->{site};
    my $locale = $c->stash->{current_locale_code} || $site->locale;
    my $home_page = $site->home_page;
    if ($home_page and $home_page =~ m{^(/[a-z][a-z0-9/-]*)$}) {
        $target = $c->uri_for($1);
    }
    elsif ($site->multilanguage and
        (my $locindex = $site->titles->special_by_uri('index-' . $locale))) {
        $target = $c->uri_for($locindex->full_uri);
    }
    elsif (my $index = $site->titles->special_by_uri('index')) {
        $target = $c->uri_for($index->full_uri);
    }
    $c->res->redirect($target);
}

sub catch_all :Chained('/site') :PathPart('') Args {
    my ($self, $c, $try) = @_;
    my $fallback;
    if ($try) {
        my $try_uri = AmuseWikiFarm::Utils::Amuse::muse_naming_algo($try);
        my $query = { 'me.uri' => $try_uri };
        if (my $site = $c->stash->{site}) {
            if (my $text = $site->titles->published_all->by_uri($try_uri)->first) {
                $fallback = $text->full_uri;
            }
            elsif (my $cat = $site->categories->with_texts->by_uri($try_uri)->first) {
                $fallback = $cat->full_uri;
            }
            elsif (my $red = $site->redirections->by_uri($try_uri)->first) {
                $fallback = $red->full_dest_uri;
            }
        }
    }
    if ($fallback) {
        $c->response->redirect($c->uri_for($fallback));
        $c->detach();
    }
    else {
        $c->detach('not_found');
    }
}

=head2 end

Attempt to render a view, if needed.

If the site has a theme, add that at the beginning of the TT's include
path.

=cut

sub end : ActionClass('RenderView') {
    my ($self, $c) = @_;

    # before passing the thing to the template, strip <> from page_title
    if ($c->stash->{page_title}) {
        $c->stash->{page_title} =~ s/<.*?>//g;
    }

    # be sure to always pass the current_locale_code and default to english
    unless ($c->stash->{current_locale_code}) {
        $c->stash(current_locale_code => 'en');
    }
}

=head1 AUTHOR

Marco Pessotto <melmothx@gmail.com>

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

__PACKAGE__->meta->make_immutable;

1;
