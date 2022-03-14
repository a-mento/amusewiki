package AmuseWikiFarm::Controller::OPDS;
use Moose;
use namespace::autoclean;

BEGIN { extends 'Catalyst::Controller'; }

use AmuseWikiFarm::Log::Contextual;
use DateTime;
use AmuseWikiFarm::Utils::Amuse qw/clean_html/;

=head1 NAME

AmuseWikiFarm::Controller::OPDS - Catalyst Controller

=head1 DESCRIPTION

Catalyst Controller.

=head1 METHODS

=cut


=head2 root

=cut

sub root :Chained('/site') :PathPart('opds') :CaptureArgs(0) {
    my ($self, $c) = @_;
    # pick the model and stash it.
    my $feed = $c->model('OPDS');
    $c->stash->{site}->initialize_opds_feed($feed);
}

sub start :Chained('root') :PathPart('') :Args(0) {
    my ($self, $c) = @_;
    $c->detach($c->view('Atom'));
}

sub titles :Chained('root') :PathPart('titles') :Args {
    my ($self, $c, $page) = @_;
    my $feed = $c->model('OPDS');
    my $titles = $c->stash->{site}->titles->published_texts;
    if ($self->populate_acquisitions($feed, '/opds/titles/',  $c->loc('Titles'), $titles, $page)) {
        $c->detach($c->view('Atom'));
    }
    else {
        $c->detach('/not_found');
    }

}

sub new_entries :Chained('root') :PathPart('new') :Args {
    my ($self, $c, $page) = @_;
    my $feed = $c->model('OPDS');
    my $titles = $c->stash->{site}->titles->published_texts->sort_by_pubdate_desc;
    if ($self->populate_acquisitions($feed, '/opds/new/',  $c->loc('Latest entries'), $titles, $page)) {
        $c->detach($c->view('Atom'));
    }
    else {
        $c->detach('/not_found');
    }
}

sub clean_root :Chained('root') :PathPart('') :CaptureArgs(0) {
    my ($self, $c) = @_;
    my $feed = $c->model('OPDS');
    # remove the new from leaves navigations
    my @navs = grep { $_->rel ne 'new' } @{$feed->navigations};
    $feed->navigations(\@navs);
}

sub all_categories :Chained('clean_root') :PathPart('category') :CaptureArgs(1) {
    my ($self, $c, $category_type) = @_;
    my $site = $c->stash->{site};
    my $ct = $site->site_category_types->active->find({ category_type => $category_type });
    unless ($ct) {
        $c->detach('/not_found');
        return;
    }
    my $cats = $c->stash->{site}->categories->active_only_by_type($category_type);
    $c->stash(feed_rs => $cats,
              category_type => $ct,
             );
}

sub categories :Chained('all_categories') :PathPart('') :Args(0) {
    my ($self, $c) = @_;
    my $feed = $c->model('OPDS');
    my $page = $self->validate_page($c->request->params->{page});
    my $ct = $c->stash->{category_type};
    my $ctype = $ct->category_type;
    $feed->add_to_navigations_new_level(
                                        href => "/opds/category/${ctype}?page=${page}",
                                        title => $c->loc($ct->name_plural),
                                        description => $c->loc($ct->name_plural),
                                       );

    my $rs = $c->stash->{feed_rs}->search(undef, {
                                                  rows => 5,
                                                  page => $page,
                                                 });
    my $pager = $rs->pager;
    while (my $cat = $rs->next) {
        $feed->add_to_navigations(
                                  href => '/opds/category/' . $ctype . '/'. $cat->uri,
                                  title => $c->loc($ct->name_singular) . ' / ' . $c->loc($cat->name),
                                  acquisition => 1,
                                 );
    }
    $self->add_pager($feed, $pager,
                     "/opds/category/" . $ct->category_type . '?page=',
                     $c->loc($ct->name_plural));
    $c->detach($c->view('Atom'));
}

sub category :Chained('all_categories') :PathPart('') :Args {
    my ($self, $c, $uri, $page) = @_;
    die "shouldn't happen" unless $uri;
    my $cats = $c->stash->{feed_rs};
    my $feed = $c->model('OPDS');
    my $ct = $c->stash->{category_type};
    my $ctype = $ct->category_type;
    # create the up rel
    $feed->add_to_navigations_new_level(
                                        href => "/opds/category/$ctype",
                                        title => $c->loc($ct->name_plural),
                                        description => $c->loc($ct->name_plural),
                                       );





    if (my $cat = $cats->find({ uri => $uri })) {

        my $titles = $cat->titles->published_texts;
        if ($self->populate_acquisitions($feed, "/opds/category/$ctype/$uri/", $c->loc($cat->name),
                                         $titles,
                                         $page)) {
            $c->detach($c->view('Atom'));
            return;
        }
    }
    $c->detach('/not_found');
}

sub search :Chained('clean_root') :PathPart('search') :Args(0) {
    my ($self, $c) = @_;
    my $feed = $c->model('OPDS');
    my $site = $c->stash->{site};
    my $xapian = $site->xapian;
    my $query = $c->request->params->{query} // '';
    my $page = $self->validate_page($c->request->params->{page});
    my $base = $c->uri_for($c->action, { query => $query })->path_query . '&page=';
    $feed->add_to_navigations_new_level(
                                        acquisition => 1,
                                        href => $base . $page,
                                        title => $c->loc('Search results'),
                                        description => $c->loc('texts sorted by author'),
                                       );
    if ($query) {
        my $res = $xapian->faceted_search(facets => 0,
                                          page => $page,
                                          locale => $c->stash->{current_locale_code},
                                          query => $query);
        if (my @results = @{$res->matches}) {
            my $pager = $res->pager;
            $feed->search_result_pager($pager);
            $feed->search_result_terms($query);
            $self->add_pager($feed, $pager, $base, $c->loc('Search results'));
            foreach my $match (@results) {
                if (my $title = $site->titles->text_by_uri($match->{pagedata}->{uri})) {
                    if (my $entry = $title->opds_entry) {
                        $feed->add_to_acquisitions(%$entry);
                    }
                }
            }
        }
    }
    $c->detach($c->view('Atom'));
}

# legacy


sub authors :Chained('root') :PathPart('authors') :Args {
    my ($self, $c, @args) = @_;
    if (@args) {
        my $uri = $c->uri_for_action('/opds/category', [ 'author' ],  @args);
        log_debug { "Redirecting to $uri" };
        $c->response->redirect($uri, 301);
    }
    else {
        my $uri = $c->uri_for_action('/opds/categories', [ 'author' ]);
        log_debug { "Redirecting to $uri" };
        $c->response->redirect($uri, 301);
    }
}

sub topics :Chained('root') :PathPart('topics') :Args {
    my ($self, $c, @args) = @_;
    if (@args) {
        my $uri = $c->uri_for_action('/opds/category', [ 'topic' ], @args);
        log_debug { "Redirecting to $uri" };
        $c->response->redirect($uri, 301);
    }
    else {
        my $uri = $c->uri_for_action('/opds/categories', [ 'topic' ]);
        log_debug { "Redirecting to $uri" };
        $c->response->redirect($uri, 301);
    }
}



sub add_pager :Private {
    my ($self, $feed, $pager, $base, $description) = @_;
    if ($pager->current_page > $pager->last_page) {
        return;
    }
    if ($pager->total_entries > $pager->entries_per_page) {
        log_debug { "Adding pagination for page " . $pager->current_page };
        foreach my $ref (qw/first last next previous/) {
            my $pager_method = $ref . '_page';
            if (my $linked_page = $pager->$pager_method) {
                log_debug { "$ref is $linked_page" };
                $feed->add_to_navigations(
                                          rel => $ref,
                                          href => $base . $linked_page,
                                          description => $description,
                                          acquisition => 1,
                                         );
            }
            else {
                log_debug { "$ref has no page" };
            }
        }
    }
}

sub populate_acquisitions :Private {
    my ($self, $feed, $base, $description, $rs, $page) = @_;
    die unless ($feed && $base && $description && $rs);
    # this is a dbic search
    my $titles = $rs->search(undef, { page => $self->validate_page($page), rows => 5 });
    my $pager = $titles->pager;
    $feed->add_to_navigations_new_level(
                                        href => $base . $pager->current_page,
                                        title => $description,
                                        acquisition => 1,
                                       );
    $self->add_pager($feed, $pager, $base, $description);
    my $return = 0;
    while (my $title = $titles->next) {
        if (my $entry = $title->opds_entry) {
            $feed->add_to_acquisitions(%$entry);
            $return++;
        }
    }
    return $return;
}

sub validate_page :Private {
    my ($self, $page) = @_;
    my $valid = 1;
    if ($page and $page =~ m/\A[1-9][0-9]*\z/) {
        $valid = $page;
    }
    return $valid;
}


=encoding utf8

=head1 AUTHOR

Marco Pessotto <melmothx@gmail.com>

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

__PACKAGE__->meta->make_immutable;

1;
