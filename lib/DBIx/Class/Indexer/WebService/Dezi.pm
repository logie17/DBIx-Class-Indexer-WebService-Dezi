package DBIx::Class::Indexer::WebService::Dezi;

use Moose;

use Dezi::Client;
use Scalar::Util ();

=head1 NAME

DBIx::Class::Indexer::WebService::Dezi - The great new DBIx::Class::Indexer::WebService::Dezi!

=head1 VERSION

Version 0.01

=cut

our $VERSION = '0.01';

around BUILDARGS => sub {
    my ( $orig, $class, $connect_info, $source ) = @_;
    return $class->$orig( connect_info => $connect_info, source => $source );
};

=head1 SYNOPSIS

This module was inspired (and borrowed some) by DBIx::Class::Indexer::WebService::Solr.
In fact it uses DBIx::Class::Indexer as its abstract class.  This indexer allows one to 
use a Dezi::Client to update the index on "insert", "update", or "delete".

    package MyApp::Schema::Foo; 
    use base 'DBIx::Class';

    __PACKAGE__->load_components(qw[ Indexed ] );
    __PACKAGE__->set_indexer('WebService::Dezi', { server => 'http://localhost:5000', content_type => 'application/json' });
    
    __PACKAGE__->table('person');
    
    __PACKAGE__->add_columns(
        person_id => {
            data_type       => 'varchar',
            size            => '36',
            is_nullable     => 0,
        },
        name => {
            data_type => 'varchar',
            is_nullable => 0,
            indexed => 1 
        },
        age => {
            data_type => 'integer',
            is_nullable => 0,
        },
        image_path => {
            data_type       => 'varchar',
            size            => '128',
            indexed         => 1,
        },
        email => {
            data_type => 'varchar',
            size=>'128',
        },
        created => {
            data_type => 'timestamp',
            set_on_create => 1,
            is_nullable => 0,
        },
    );


=head1 ATTRIBUTES

=head2 connect_info

Connect info parameters.

=cut
has connect_info => (
    is => 'rw'
);

=head2 content_type

Connect info parameters.

=cut
has content_type => (
    is      => 'rw',
    default => sub { 'application/xml' }
);

=head2 source

Source object

=cut
has source => (
    is => 'rw'
);

=head2 _obj

Internal dezi object.

=cut
has _obj => (
    is => 'rw'
);

=head2 _field_prep

Used for noramalization of fields.

=cut
has _field_prep => (
    traits  => ['Hash'],
    is      => 'rw',
    isa     => 'HashRef[Str]',
    default   => sub { {} },
    handles   => {
          set_field_prep => 'set',
          get_field_prep => 'get',
    }
);

=head1 ATTRIBUTES

=head2 as_document( $self, $object )

Handles the insert operation. Generates a XML document that will be
indexed by the dezi service.

=cut

sub as_document {
    my ( $self, $object ) = @_;

    my $fields = $object->index_fields;

    my %output;


    # for each field...
    for my $name ( keys %$fields ) {
        my $opts    = $fields->{$name};
        my @values  = $self->value_for_field( $object, $name );
    
        for( @values ) {
            $output{$name} = [ @values ]
        }
    }

    my $output_str = $self->_generate_document(\%output);

    return \$output_str;
}


=head2 BUILD( $self )

Creates a new Dezi::Client object and normalizes the fields to be
indexed.

=cut
sub BUILD {
    my ( $self ) = @_;

    $self->setup_fields( $self->source );

    my $server       = $self->connect_info->{ server };
    my $content_type = $self->connect_info->{content_type} || $self->content_type;;

    my $dezi         = Dezi::Client->new( server => $server ); 

    $self->_obj( $dezi );
    $self->content_type($content_type);

    return $self;

}


=head2 update_or_create_document( $object )

Handles the insert operation.

=cut

sub update_or_create_document {
    my $self   = shift;
    my $object = shift;
    my $dezi  = $self->_obj;

    $self->setup_fields( ref $object );

    $dezi->index( $self->as_document( $object ), $object->id, $self->content_type );

}


=head2 value_for_field( $object, $key )

Uses the indexed fields information to determine how to get
the values for C<$key> out of C<$object>. 

The logic here was borrowed from DBIx::Class::Indexer::WebService::Solr

=cut

sub value_for_field {
    my( $self, $object, $key ) = @_;
    my $info   = $object->index_fields->{ $key };
    my $source = $info->{ source } || $key;

    if( ref $source eq 'CODE' ) {
        return $source->( $object );
    }
    elsif( not ref $source ) {
        my @accessors = split /\./, $source;
        
        # no use calling 'me' on myself...
        shift @accessors if lc $accessors[ 0 ] eq 'me';
        
        # traverse accessors
        my @values = $object;
        for my $accessor ( @accessors ) {
            @values = grep { defined }
                 map  {
                       Scalar::Util::blessed( $_ ) and $_->can( $accessor ) ? $_->$accessor
                     : ref $_ eq 'HASH' ? $_->{ $accessor }
                     : undef
                 } @values;
        }
        return wantarray ? @values : $values[ 0 ];
    }
}

=head2 setup_fields( $source )

Normalizes the index fields so they all have hashref members with an optional
boost key.

=cut
sub setup_fields {
    my( $self, $source ) = @_;

    return if $self->get_field_prep( $source );

    my $fields = $source->index_fields;
  
    # normalize field defs
    for my $key ( keys %$fields ) {
        $fields->{ $key } = { } if !ref $fields->{ $key };
    }

    $self->set_field_prep( $source => 1 );
}

=head2 delete( $object )

Handles the delete operation.

=cut

sub delete {
    my $self   = shift;
    my $object = shift;
    my $dezi  = $self->_obj;

    $self->setup_fields( ref $object );

    my $id = $self->value_for_field( $object, 'id' );

    $dezi->delete( $id );  
}

=head2 insert( $object )

Handles the insert operation.

=cut

sub insert {
    my $self   = shift;
    my $object = shift;
    $self->update_or_create_document( $object );
}

=head2 update( $object )

Handles the update operation.

=cut

sub update {
    my $self   = shift;
    my $object = shift;
    
    $self->update_or_create_document( $object );
}

sub _generate_document {
    my ( $self, $fields ) = @_;

    my $output_str;
    if ( $self->content_type eq 'application/xml' ) {
        require XML::Simple;
        my $xs = XML::Simple->new;
        $output_str = $xs->XMLout($fields, NoAttr => 1, RootName=>'doc',);
    } elsif ( $self->content_type eq 'application/json' ) {
        require JSON;
        $output_str = JSON::encode_json({ doc => $fields });
    }

    return $output_str;
}

=head1 AUTHOR

Logan Bell, C<< <loganbell at gmail.com> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-dbix-class-indexer-webservice-dezi at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=DBIx-Class-Indexer-WebService-Dezi>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc DBIx::Class::Indexer::WebService::Dezi


You can also look for information at:

=over 4

=item * RT: CPAN's request tracker (report bugs here)

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=DBIx-Class-Indexer-WebService-Dezi>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/DBIx-Class-Indexer-WebService-Dezi>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/DBIx-Class-Indexer-WebService-Dezi>

=item * Search CPAN

L<http://search.cpan.org/dist/DBIx-Class-Indexer-WebService-Dezi/>

=back


=head1 ACKNOWLEDGEMENTS


=head1 LICENSE AND COPYRIGHT

Copyright 2011 Logan Bell.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See http://dev.perl.org/licenses/ for more information.


=cut

1; # End of DBIx::Class::Indexer::WebService::Dezi
