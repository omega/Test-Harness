package TAP::Formatter::Console::ParallelSession;

use strict;
use File::Spec;
use File::Path;
use TAP::Formatter::Console::Session;
use Carp;

use constant WIDTH => 72;    # Because Eric says
use vars qw($VERSION @ISA);

@ISA = qw(TAP::Formatter::Console::Session);

my %shared;

sub _initialize {
    my ( $self, $arg_for ) = @_;

    $self->SUPER::_initialize($arg_for);
    my $formatter = $self->formatter;

    # Horrid bodge. This creates our shared context per harness. Maybe
    # TAP::Harness should give us this?
    my $context = $shared{$formatter} ||= $self->_create_shared_context;
    push @{ $context->{active} }, $self;

    return $self;
}

sub _create_shared_context {
    my $self = shift;
    return {
        active => [],
        tests  => 0,
        fails  => 0,
    };
}

sub _need_refresh {
    my $self      = shift;
    my $formatter = $self->formatter;
    $shared{$formatter}->{need_refresh}++;
}

=head1 NAME

TAP::Formatter::Console::ParallelSession - Harness output delegate for parallel console output

=head1 VERSION

Version 3.14

=cut

$VERSION = '3.14';

=head1 DESCRIPTION

This provides console orientated output formatting for L<TAP::Harness::Parallel>.

=head1 SYNOPSIS

=cut

=head1 METHODS

=head2 Class Methods

=head3 C<header>

Output test preamble

=cut

sub header {
    my $self = shift;
    $self->_need_refresh;
}

sub _refresh {
}

sub _clear_line {
    my $self = shift;
    $self->formatter->_output( "\r" . ( ' ' x WIDTH ) . "\r" );
}

sub _output_ruler {
    my $self      = shift;
    my $formatter = $self->formatter;
    return if $formatter->really_quiet;

    my $context = $shared{$formatter};

    my $ruler = sprintf( "===( %7d )", $context->{tests} );
    $ruler .= ( '=' x ( WIDTH - length $ruler ) );
    $formatter->_output("\r$ruler");
}

=head3 C<result>

  Called by the harness for each line of TAP it receives .

=cut

sub result {
    my ( $self, $result ) = @_;
    my $formatter = $self->formatter;
    $self->_refresh;

    # my $really_quiet = $formatter->really_quiet;
    # my $show_count   = $self->_should_show_count;

    if ( $result->is_test ) {
        my $context = $shared{$formatter};
        $context->{tests}++;

	my $active = $context->{active};
	if ( @$active == 1 ) {
            # There is only one test, so use the serial output format.
            return $self->SUPER::result( $result );
        }

        my $ceiling = $context->{tests} / 5;

        # Find the next highest power of two, in linear time.
        my $binary = unpack "B*", pack "N", $ceiling;
        $binary =~ /^0+/;
        my $test_print_modulus = 1 << length $binary;

        unless ( $context->{tests} % $test_print_modulus ) {
            $self->_output_ruler;
        }
    }
    elsif ( $result->is_bailout ) {
        $formatter->_failure_output(
                "Bailout called.  Further testing stopped:  "
              . $result->explanation
              . "\n" );
    }
}

=head3 C<close_test>

=cut

sub close_test {
    my $self      = shift;
    my $name      = $self->name;
    my $parser    = $self->parser;
    my $formatter = $self->formatter;
    my $context   = $shared{$formatter};

    unless ( $formatter->really_quiet ) {
        $self->_clear_line;

        # my $output = $self->_output_method;
        $formatter->_output(
            $formatter->_format_name( $self->name ),
            ' '
        );
    }

    if ( $parser->has_problems ) {
        $self->_output_test_failure($parser);
    }
    else {
        $formatter->_output("ok\n")
          unless $formatter->really_quiet;
    }


    # $self->SUPER::close_test;
    my $active = $context->{active};

    my @pos = grep { $active->[$_]->name eq $name } 0 .. $#$active;

    die "Can't find myself" unless @pos;
    splice @$active, $pos[0], 1;

    $self->_need_refresh;

    if (@$active > 1) {
        $self->_output_ruler;
    } elsif (@$active < 1) {
        # $self->formatter->_output("\n");
        delete $shared{$formatter};
    }
}

1;
