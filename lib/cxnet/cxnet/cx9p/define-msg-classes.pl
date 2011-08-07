#!/usr/bin/perl

use strict;

my $line;
# Search for enum
while ($line !~ /^\s*enum/) { $line = <STDIN> or last; }
while ($line !~ /{/) { $line = <STDIN> or last; }

# Read in enum items
my %types = ();
my $ord = 0;
while ($line = <STDIN>) {
    if ($line =~ /^\s*([TR]([^\s=,]+))(\s*=\s*(\d+))?\s*,?\s*(\/\*\s*(.*)\s*\*\/)?$/) {
	my $base = $2;
	$ord = $4 if $3;
	my $type = { ord => $ord, name => $1, comment => $6 };
	$types{$base} = { ord => $ord } unless $types{$base};
	
	$types{$base}->{T} = $type if $type->{name} =~ /^T/;
	$types{$base}->{R} = $type if $type->{name} =~ /^R/;
    }
    last if $line =~ /}/;
    $ord++;
}

# Prints the base class definition for a given type
sub print_base {
    my ($base) = @_;

    print "class p9${base}msgobj (p9msgobj):\n".
          "    \"\"\"\n".
          "    9P '$base' message base class\n".
          "    \"\"\"\n";
}

# Prints the T- or R-message class for a given type
sub print_tr {
    my ($type) = @_;
    (my $base = $type->{name}) =~ s/^[TR]//;

    print "class $type->{name} (Structure, p9${base}msgobj):\n".
          "    \"\"\"\n";
    print "    9P type $type->{ord} '$base' request (transmit) message class\n" if $type->{name} =~ /^T/;
    print "    9P type $type->{ord} '$base' reply (return) message class\n" if $type->{name} =~ /^R/;
    print "    Comment: $type->{comment}\n" if $type->{comment};
    print "    \"\"\"\n";
    print "    _fields_ = [\n".
	  "        (\"header\", p9msgheader),\n".
	  "    ]\n";
}

# Print out the class definitions
my $n = 0;
foreach my $base (sort { $types{$a}->{ord} <=> $types{$b}->{ord}  } keys %types) {
    print "\n" if $n > 0;
    print_base($base);
    if ($types{$base}->{T} || $types{$base}->{R}) {
	if ($types{$base}->{T}) {
	    print "\n";
	    print_tr($types{$base}->{T});
	}
	if ($types{$base}->{R}) {
	    print "\n";
	    print_tr($types{$base}->{R});
	}
    }
    $n++;
}

# Prints a message types tuple addon
sub print_next_class {
    my (@tuple) = @_;

    if (@tuple) {
	print "p9msgclasses += tuple([".join(', ', map { $_->{name} } @tuple)."]) ";
	print "# ".join(', ', map { $_->{ord} } @tuple)."\n";
    }
}

# Print out the message types tuple

print "\n";
print "\"\"\"\n";
print "The tuple of all defined message classes\n";
print "\"\"\"\n";
print "p9msgclasses = tuple()\n";

my %ords = ();
foreach my $type (values %types) {
    $ords{$type->{T}->{ord}} = $type->{T} if $type->{T};
    $ords{$type->{R}->{ord}} = $type->{R} if $type->{R};
}

my $n = 0;
my @tuple = ();
while ($n <= 255) {
    if (exists $ords{$n}) {
	if (@tuple and $ords{$n}->{name} =~ /^T/ and $n < 255 and exists $ords{$n + 1}) {
	    print_next_class(@tuple);
	    @tuple = ($ords{$n});
	} else {
	    push(@tuple, $ords{$n});
	}
	$n++;
    } else {
	print_next_class(@tuple);
	@tuple = ();
	my $min = $n;
	while ($n <= 255 and not exists $ords{$n}) { $n++; }
	print "p9msgclasses += tuple([None]*".($n - $min).") # Types for $min..".($n - 1)." are not defined\n";
    }
}
print_next_class(@tuple);
