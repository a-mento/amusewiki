use utf8;
package AmuseWikiFarm::Schema::Result::MuseHeader;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

AmuseWikiFarm::Schema::Result::MuseHeader - Raw title headers

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

=head1 TABLE: C<muse_header>

=cut

__PACKAGE__->table("muse_header");

=head1 ACCESSORS

=head2 title_id

  data_type: 'integer'
  is_foreign_key: 1
  is_nullable: 0

=head2 muse_header

  data_type: 'varchar'
  is_nullable: 0
  size: 255

=head2 muse_value

  data_type: 'text'
  is_nullable: 1

=head2 muse_value_html

  data_type: 'text'
  is_nullable: 1

=cut

__PACKAGE__->add_columns(
  "title_id",
  { data_type => "integer", is_foreign_key => 1, is_nullable => 0 },
  "muse_header",
  { data_type => "varchar", is_nullable => 0, size => 255 },
  "muse_value",
  { data_type => "text", is_nullable => 1 },
  "muse_value_html",
  { data_type => "text", is_nullable => 1 },
);

=head1 PRIMARY KEY

=over 4

=item * L</title_id>

=item * L</muse_header>

=back

=cut

__PACKAGE__->set_primary_key("title_id", "muse_header");

=head1 RELATIONS

=head2 title

Type: belongs_to

Related object: L<AmuseWikiFarm::Schema::Result::Title>

=cut

__PACKAGE__->belongs_to(
  "title",
  "AmuseWikiFarm::Schema::Result::Title",
  { id => "title_id" },
  { is_deferrable => 0, on_delete => "CASCADE", on_update => "CASCADE" },
);


# Created by DBIx::Class::Schema::Loader v0.07049 @ 2022-06-05 09:02:32
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:sU2OMLEdKfIgQPWD0P5IHw

sub as_html {
    shift->muse_value_html;
}


__PACKAGE__->meta->make_immutable;
1;
