package AmuseWikiFarm::Controller::User;
use Moose;
with 'AmuseWikiFarm::Role::Controller::HumanLoginScreen';

use namespace::autoclean;

BEGIN { extends 'Catalyst::Controller'; }

=head1 NAME

AmuseWikiFarm::Controller::User - Catalyst Controller

=head1 DESCRIPTION

Catalyst Controller.

=head1 METHODS

Canonical methods to login and logout users

=cut

=head2 login

Path: /login

Upon login, first the username is checked. We don't call the
authenticate method if the user does not exists, or if it belongs to
another site.

Also, it install the C<i_am_human> token in the session, so even after
logout, the user is still marked as human.

=head2 logout

Path: /logout

Log the user out, but do not reset the session.

=head2 human

Path: /human

Url where the form for the antispam question should be posted. It
install in the session the key C<i_am_human>.

=cut

use URI;
use URI::QueryParam;
use Try::Tiny;
use AmuseWikiFarm::Log::Contextual;
use AmuseWikiFarm::Utils::Amuse ();
use constant { MAXLENGTH => 255, MINPASSWORD => 7 };

sub authorize_ip :Chained('/site_no_auth') :PathPart('authorize-ip') :Args(1) {
    my ($self, $c, $token) = @_;
    $self->redirect_to_secure($c);
    # first, check if the token is present for any user
    my $site = $c->stash->{site};
    my $ip = $c->req->address;
    my $ok;
    if ($token) {
      USER:
        foreach my $user ($c->model('DB::User')->search({ api_access_token => $token })) {
            if ($user->roles->find({ role => 'root' }) or
                $user->user_sites->find({ site_id => $site->id })) {
                log_info { "IP $ip authorized by " . $user->username };
                my %update = (
                              expire_epoch => time() + 60 * 60 * 4,
                              granted_by_username => $user->username,
                             );
                if (my $existing = $site->whitelist_ips->find({ ip => $ip })) {
                    if ($existing->expire_epoch) {
                        $existing->update(\%update);
                    }
                    else {
                        log_debug { "IP is already permanently whitelisted" };
                    }
                }
                else {
                    $site->add_to_whitelist_ips({
                                                 ip => $ip,
                                                 user_editable => 0,
                                                 %update,
                                                });
                }
                $ok++;
                last USER;
            }
        }
    }
    if ($ok) {
        $c->response->content_type('text/plain');
        $c->response->body("$ip has been authorized\n");
    }
    else {
        $c->detach('/not_permitted');
    }
}

sub refresh_api_access_token :Chained('/site_user_required') :PathPart('refresh-api-access-token') :Args(0) {
    my ($self, $c) = @_;
    die unless $c->user_exists;
    my $username = $c->user->get('username');
    if ($username) {
        log_info { "Resetting the token for $username" };
        $c->model('DB::User')->find({ username => $username })->get_api_access_token({ reset => 1 });
        $c->stash->{site}->whitelist_ips->search({ granted_by_username => $username })->delete;
    }
    $c->flash(status_msg => $c->loc("Token refreshed"));
    $c->response->redirect($c->uri_for_action('/console/git_display'));
}

# used by /login and /reset_password
sub secure_no_user :Chained('/site_no_auth') :PathPart('') :CaptureArgs(0) {
    my ( $self, $c ) = @_;
    if ($c->user_exists) {
        $c->flash(status_msg => $c->loc("You are already logged in"));
        $c->response->redirect($c->uri_for('/'));
        return;
    }
    $self->redirect_to_secure($c);
}


sub login :Chained('secure_no_user') :PathPart('login') :Args(0) {
    my ($self, $c) = @_;
    if ($self->check_login($c)) {
        $c->response->redirect($c->uri_for('/'));
    }
    else {
        die "Unreachable";
    }
}

sub reset_password :Chained('secure_no_user') :PathPart('reset-password') :Args(0) {
    my ($self, $c) = @_;
    $c->stash(
              page_title => $c->loc('Reset password'),
             );
    my $params = $c->request->body_params;
    if ($params->{submit} && $params->{email} && $params->{email} =~ m/\w/) {
        my $site = $c->stash->{site};
        log_debug { "resetting password for $params->{email}" };
        foreach my $user ($site->users->set_reset_token($params->{email})) {
            log_info { "Set reset token for " . $user->username };
            my $dt = DateTime->from_epoch(epoch => $user->reset_until,
                                          locale => $c->stash->{current_locale_code});
            my $valid_until = $dt->format_cldr($dt->locale->datetime_format_long);
            my $url = $c->uri_for_action('/user/reset_password_confirm',
                                         [ $user->username, $user->reset_token_plain ]);
            $site->send_mail(resetpassword => {
                                                             to => $user->email,
                                                             from => $site->mail_from_default,
                                                             reset_url => $url,
                                                             host => $site->canonical,
                                                             username => $user->username,
                                                             sitename => $site->sitename || $site->canonical,
                                                            });
        }
    }
}

sub reset_password_confirm :Chained('secure_no_user') :PathPart('reset-password') :Args(2) {
    my ($self, $c, $username, $token) = @_;
    my $users = $c->stash->{site}->users;
    if (my $user = $users->reset_password_token_is_valid($username, $token)) {
        # Dlog_debug { "Params are $_" } $c->request->body_params;
        my $pwd = $c->request->body_params->{password};
        my $pwd_repeat = $c->request->body_params->{passwordrepeat};
        if ($pwd && $pwd_repeat) {
            my ($validated, @errors) = $users->validate_params(password => $pwd,
                                                               passwordrepeat => $pwd_repeat,
                                                              );
            if (@errors) {
                Dlog_info { "Found error in password validation $_" } \@errors;
                $c->flash(error_msg => join ("\n", map { $c->loc($_) } @errors));
            }
            elsif ($validated->{password}) {
                $user->update({
                               password => $validated->{password},
                               reset_until => 0,
                              });
                $c->flash(status_msg => $c->loc('Your password was reset, now you can login with it'));
                $c->response->redirect($c->uri_for_action('/user/login'));
                return;
            }
        }
        $c->stash(username => $username);
    }
    else {
        $c->flash(error_msg => $c->log('The reset link is invalid or expired. Please try again'));
        $c->response->redirect($c->uri_for_action('/user/reset_password'));
    }
}

sub logout :Chained('/site') :PathPart('logout') :Args(0) {
    my ($self, $c) = @_;
    if ($c->user_exists) {
        $c->logout;
        $c->flash(status_msg => $c->loc('You have logged out'));
    }
    $c->response->redirect($c->uri_for('/'));
}

sub human :Chained('/site') :PathPart('human') :Args(0) {
    my ($self, $c) = @_;
    if ($self->check_human($c)) {
        $c->response->redirect($c->uri_for('/'));
    }
}

sub user :Chained('/site_user_required') :CaptureArgs(0) {
    my ($self, $c) = @_;
    $self->check_login($c);
    $c->stash(full_page_no_side_columns => 1);
}

sub create :Chained('user') :Args(0) {
    my ($self, $c) = @_;
    # start validating
    my %params = %{ $c->request->params };
    if ($params{create}) {
        # check if all the fields are in place
        my %to_validate;
        log_debug { "Validating the parameters" };
        my $missing = 0;
        foreach my $f (qw/username password passwordrepeat
                          email emailrepeat/) {
            if (my $v = $params{$f}) {
                $to_validate{$f} = $params{$f};
            }
            else {
                log_debug { $f . " is missing in the params" };
                $missing++;
            }
        }
        if ($missing) {
            $c->flash(error_msg => $c->loc('Some fields are missing, all are required'));
            return;
        }
        my $users = $c->model('DB::User');
        my ($insert, @errors) = $users->validate_params(%to_validate);
        my %insertion;

        if ($insert and !@errors) {
            %insertion = %$insert;
        }
        else {
            Dlog_debug { "error: insert and errors: $_" } [ $insert, @errors ];
            $c->flash(error_msg => join ("\n", map { $c->loc($_) } @errors));
            return;
        }
        die "shouldn't happen" unless $insertion{username};

        # at this point we should be good, if the user doesn't exist
        if ($users->find({ username => $insertion{username} })) {
            log_debug { "User already exists" };
            $c->flash(error_msg => $c->loc('Such username already exists'));
            return;
        }
        $insertion{created_by} = $c->user->get('username');
        Dlog_debug { "user insertion is $_" } \%insertion;

        my $user = $users->create(\%insertion);
        $user->set_roles([{ role => 'librarian' }]);
        $c->stash->{site}->add_to_users($user);
        $user->discard_changes;

        $c->flash(status_msg => $c->loc("User [_1] created!", $user->username));
        $c->stash(user => $user);

        if (my $mail_from = $c->stash->{site}->mail_from) {
            my %mail = (
                        to => $user->email,
                        cc => $c->user->get('email'),
                        from => $mail_from,
                        home => $c->uri_for('/'),
                        username  => $user->username,
                        password => $insertion{password},
                        create_url => $c->uri_for_action('/user/create'),
                        edit_url => $c->uri_for_action('/user/edit', [ $user->id ]),
                       );
            if ($c->stash->{site}->send_mail(newuser => \%mail)) {
                $c->flash->{status_msg} .= "\n" . $c->loc('Email sent!');
            }
            else {
                $c->flash(error_msg => $c->loc('Error sending mail!'));
            }
        }
        $c->response->redirect($c->uri_for('/'));
    }
}

sub get_user :Chained('user') :PathPart('edit') :CaptureArgs(1) {
    my ($self, $c, $id) = @_;
    unless ($c->user->get('id') eq $id or
            $c->check_user_roles(qw/root/)) {
        $c->detach('/not_permitted');
        return;
    }
    my $user = $c->model('DB::User')->find($id);
    unless ($user) {
        log_info { "User $id not found!" };
        $c->detach('/not_found');
        return;
    }
    $c->stash(user => $user);
}


sub edit :Chained('get_user') :PathPart('') :Args(0) {
    my ($self, $c) = @_;
    my $user = $c->stash->{user} or die;
    my %params = %{ $c->request->body_params };
    my $current_lang_choice = $user->preferred_language || '';
    if ($params{update}) {
        my %validate = (preferred_language => $params{preferred_language} || '');
        my @msgs;
        if ($params{passwordrepeat} && $params{password}) {
            $validate{passwordrepeat} = $params{passwordrepeat};
            $validate{password} = $params{password};
            push @msgs, $c->loc("Password updated");
        }
        # email
        if ($params{emailrepeat} && $params{email}) {
            $validate{emailrepeat} = $params{emailrepeat};
            $validate{email} = $params{email};
            push @msgs, $c->loc("Email updated");
        }
        if ($current_lang_choice ne $validate{preferred_language}) {
            push @msgs, $c->loc("Locale updated");
        }
        Dlog_debug { "Params for validation are $_" } \%validate;
        my ($validated, @errors) = $c->model('DB::User')->validate_params(%validate);
        Dlog_debug { "Validated params are $_" } $validated;
        if ($validated and %$validated) {
            $user->update($validated);
            $user->discard_changes;
            $current_lang_choice = $validated->{preferred_language};
            $c->session(user_locale => $current_lang_choice);
            $c->flash(status_msg => join("\n", @msgs));
            return $c->response->redirect($c->uri_for_action('/user/edit', [ $user->id ]));
        }
        if (@errors) {
            $c->flash(error_msg => join("\n", map { $c->loc($_) } @errors));
        }
    }
    my %langs = %{ AmuseWikiFarm::Utils::Amuse::known_langs() };
    $langs{''} = $c->loc("Use the site locale");
    $c->stash(
              known_langs => \%langs,
              current_language => $current_lang_choice,
             );
}

sub edit_options :Chained('get_user') :PathPart('options') :Args(0) {
    my ($self, $c) = @_;
    my $user = $c->stash->{user} or die;
    my %params = %{ $c->request->body_params };
    # cheap validation, these are all numeric and enforced in the db
    if (delete $params{update}) {
        my %update = map { $_ => $params{$_} || 0 } (qw/edit_option_preview_box_height
                                                        edit_option_page_left_bs_columns
                                                        edit_option_show_filters
                                                        edit_option_show_cheatsheet/);
        try {
            $user->update(\%update);
            $c->flash(status_msg => $c->loc('User [_1] updated', $user->username));
        } catch {
            my $error = $_;
            # this shouldn't normally happen, so say "errors" and notify the admin
            Dlog_error { "Failure updating " . $user->username . "with params $_" } \%params;
            $c->flash(error_msg => $c->loc('Errors'));
        };
    }
}

sub site_config :Chained('user') :PathPart('site') :Args(0) {
    my ($self, $c) = @_;
    unless ($c->check_any_user_role(qw/admin root/)) {
        $c->detach('/not_permitted');
        return;
    }
    my $site = $c->stash->{site};
    my $esite = $c->model('DB::Site')->find($site->id);
    # this is a restricted area as well, and we post HTML and get it back verbatim.
    $c->response->header('X-XSS-Protection', 0);
    my %params = %{ $c->request->body_parameters };
    if (delete $params{edit_site}) {
        Dlog_debug { "Doing the update on $_" } \%params;
        if (my $err = $esite->update_from_params_restricted(\%params)) {
            log_debug { "Error! $err" };
            $c->flash(error_msg => $c->loc($err));
        }
    }
    $c->stash(template => 'admin/edit.tt',
              load_highlight => $site->use_js_highlight(1),
              esite => $esite,
              restricted => 1);
}

sub bookcovers :Chained('user') :PathPart('bookcovers') :Args(0) {
    my ($self, $c) = @_;
    my $user = $c->user->get_object;
    $c->stash(bookcovers => [ $user->bookcovers->all ],
              load_datatables => 1,
             );
}


=head1 AUTHOR

Marco Pessotto <melmothx@gmail.com>

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

__PACKAGE__->meta->make_immutable;

1;
