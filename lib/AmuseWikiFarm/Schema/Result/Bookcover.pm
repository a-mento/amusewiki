use utf8;
package AmuseWikiFarm::Schema::Result::Bookcover;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

AmuseWikiFarm::Schema::Result::Bookcover

=cut

use strict;
use warnings;

use Moose;
use MooseX::NonMoose;
use MooseX::MarkAsMethods autoclean => 1;
extends 'DBIx::Class::Core';

=head1 COMPONENTS LOADED

=over 4

=item * L<DBIx::Class::InflateColumn::DateTime>

=back

=cut

__PACKAGE__->load_components("InflateColumn::DateTime");

=head1 TABLE: C<bookcover>

=cut

__PACKAGE__->table("bookcover");

=head1 ACCESSORS

=head2 bookcover_id

  data_type: 'integer'
  is_auto_increment: 1
  is_nullable: 0

=head2 site_id

  data_type: 'varchar'
  is_foreign_key: 1
  is_nullable: 0
  size: 16

=head2 coverheight

  data_type: 'integer'
  is_nullable: 0

=head2 coverwidth

  data_type: 'integer'
  is_nullable: 0

=head2 spinewidth

  data_type: 'integer'
  default_value: 0
  is_nullable: 0

=head2 flapwidth

  data_type: 'integer'
  default_value: 0
  is_nullable: 0

=head2 wrapwidth

  data_type: 'integer'
  default_value: 0
  is_nullable: 0

=head2 bleedwidth

  data_type: 'integer'
  default_value: 10
  is_nullable: 0

=head2 marklength

  data_type: 'integer'
  default_value: 5
  is_nullable: 0

=head2 foldingmargin

  data_type: 'smallint'
  default_value: 0
  is_nullable: 0

=head2 created

  data_type: 'datetime'
  is_nullable: 0

=head2 user_id

  data_type: 'integer'
  is_foreign_key: 1
  is_nullable: 1

=cut

__PACKAGE__->add_columns(
  "bookcover_id",
  { data_type => "integer", is_auto_increment => 1, is_nullable => 0 },
  "site_id",
  { data_type => "varchar", is_foreign_key => 1, is_nullable => 0, size => 16 },
  "coverheight",
  { data_type => "integer", is_nullable => 0 },
  "coverwidth",
  { data_type => "integer", is_nullable => 0 },
  "spinewidth",
  { data_type => "integer", default_value => 0, is_nullable => 0 },
  "flapwidth",
  { data_type => "integer", default_value => 0, is_nullable => 0 },
  "wrapwidth",
  { data_type => "integer", default_value => 0, is_nullable => 0 },
  "bleedwidth",
  { data_type => "integer", default_value => 10, is_nullable => 0 },
  "marklength",
  { data_type => "integer", default_value => 5, is_nullable => 0 },
  "foldingmargin",
  { data_type => "smallint", default_value => 0, is_nullable => 0 },
  "created",
  { data_type => "datetime", is_nullable => 0 },
  "user_id",
  { data_type => "integer", is_foreign_key => 1, is_nullable => 1 },
);

=head1 PRIMARY KEY

=over 4

=item * L</bookcover_id>

=back

=cut

__PACKAGE__->set_primary_key("bookcover_id");

=head1 RELATIONS

=head2 bookcover_tokens

Type: has_many

Related object: L<AmuseWikiFarm::Schema::Result::BookcoverToken>

=cut

__PACKAGE__->has_many(
  "bookcover_tokens",
  "AmuseWikiFarm::Schema::Result::BookcoverToken",
  { "foreign.bookcover_id" => "self.bookcover_id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 site

Type: belongs_to

Related object: L<AmuseWikiFarm::Schema::Result::Site>

=cut

__PACKAGE__->belongs_to(
  "site",
  "AmuseWikiFarm::Schema::Result::Site",
  { id => "site_id" },
  { is_deferrable => 0, on_delete => "CASCADE", on_update => "CASCADE" },
);

=head2 user

Type: belongs_to

Related object: L<AmuseWikiFarm::Schema::Result::User>

=cut

__PACKAGE__->belongs_to(
  "user",
  "AmuseWikiFarm::Schema::Result::User",
  { id => "user_id" },
  {
    is_deferrable => 0,
    join_type     => "LEFT",
    on_delete     => "CASCADE",
    on_update     => "CASCADE",
  },
);


# Created by DBIx::Class::Schema::Loader v0.07051 @ 2024-01-26 14:19:33
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:v9tFJmUBd49AFqhmpWyskQ


# You can replace this text with custom code or comments, and it will be preserved on regeneration
__PACKAGE__->meta->make_immutable;
1;
