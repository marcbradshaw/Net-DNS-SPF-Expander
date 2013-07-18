package Net::DNS::SPF::Expander;

use Moose;
use Net::DNS::ZoneFile;
use Net::DNS::Resolver;
use MooseX::Types::IO::All 'IO_All';
use Data::Printer;

has 'input_file' => (
    is       => 'ro',
    isa      => IO_All,
    required => 1,
    coerce   => 1,
);
has 'output_file' => (
    is         => 'ro',
    isa        => IO_All,
    lazy_build => 1,
    coerce     => 1,
);
has 'parsed_file' => (
    is         => 'ro',
    isa        => 'Net::DNS::ZoneFile',
    lazy_build => 1,
);
has 'resource_records' => (
    is         => 'ro',
    isa        => 'Maybe[ArrayRef[Net::DNS::RR]]',
    lazy_build => 1,
);
has 'spf_records' => (
    is         => 'ro',
    isa        => 'Maybe[ArrayRef[Net::DNS::RR]]',
    lazy_build => 1,
);

has 'to_expand' => (
    is      => 'ro',
    isa     => 'ArrayRef[RegexpRef]',
    default => sub {
        [ qr/^a:/, qr/^mx/, qr/^include/, qr/^redirect/, ];
    },
);

has 'to_copy' => (
    is      => 'ro',
    isa     => 'ArrayRef[RegexpRef]',
    default => sub {
        [ qr/^ip4/, qr/^ip6/, qr/^ptr/, qr/^exists/, ];
    },
);

has 'to_ignore' => (
    is      => 'ro',
    isa     => 'ArrayRef[RegexpRef]',
    default => sub {
        [ qr/^(\??)all/, qr/^exp/, ];
    },
);

has 'expansions' => (
    is => 'rw',
    isa => 'HashRef',
    default => sub {{}},
);

sub _build_destination_file {
    my $self = shift;
    return $self->input_file;
}

sub _build_parsed_file {
    my $self = shift;
    return Net::DNS::ZoneFile->new( $self->input_file);
}

sub _build_resource_records {
    my $self             = shift;
    warn p $self->parsed_file;
    my @resource_records = $self->parsed_file->readfh;
    return \@resource_records;
}

sub _build_spf_records {
    my $self = shift;

    # This is crude but correct: SPF records can be both TXT and SPF.
    my @spf_records =
      grep { $_->txtdata =~ /v=spf1/ } @{ $self->resource_records };
    return \@spf_records;
}

sub write {
    my $self = shift;
}

sub _expand_spf_component {
    my ( $self, $component ) = @_;
    if (scalar(split(' ', $component))) {
        my @components = split(' ', $component);
        for my $component (@components) {
            return $component if grep {/$component/} @{$self->to_ignore};
            return $component if grep {/$component/} @{$self->to_copy};
            $self->_expand_spf_component($component);
        }
    }
    return $component if grep {/$component/} @{$self->to_ignore};
    return $component if grep {/$component/} @{$self->to_copy};

    $self->_expand_spf_component($component);
}

sub expand {
    my $self = shift;
    my %spf_hash = ();
    for my $spf_record (@{$self->spf_records}) {
        my @spf_components = split(' ', $spf_record->txtdata);
        for my $spf_component (@spf_components) {
            $spf_hash{$spf_record->name}{$spf_component} = $self->_expand_spf_component($spf_component);            
        }
    }
}

1;
