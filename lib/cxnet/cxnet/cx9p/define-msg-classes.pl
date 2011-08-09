#!/usr/bin/perl

use strict;
use locale;

# Look around
(my $dir = $0) =~ s,/[^/]+$,,;

my $line;
# Search for enum
while ($line !~ /^\s*enum/) { $line = <STDIN> or last; }
while ($line !~ /{/) { $line = <STDIN> or last; }

# Returns the array type with the specified parameters
sub arraytype {
    my ($pref, $cfield, $dfield) = @_;

    if ($cfield->[1] =~ /^(c_ubyte|c_uint(8|16|32))$/) {
	my $csize = $2 || "8";
	return "$pref$csize($dfield->[1])";
    } else {
	die "Unsupported array counter type: $cfield->[0]";
    }
}

# Returns the field type for a given field name and a type notation
sub fieldtype {
    my ($fname, $ftype) = @_;

    if ($ftype =~ /^\d+$/) {
	if ($ftype eq "1") {
	    return "c_ubyte";
	} elsif ($ftype eq "2") {
	    return "c_uint16";
	} elsif ($ftype eq "4") {
	    return "c_uint32";
	} elsif ($ftype eq "13" and $fname =~ /qid/) {
	    return "p9qid";
	} else {
	    return "(c_ubyte * $ftype)";
	}
    } elsif ($ftype eq "s") {
	return "p9msgstr";
    } elsif ($ftype eq "n") {
	return arraytype("p9msgarray", ["n", "c_uint16"], [$fname, "c_ubyte"]);
    }# Returns the array type with the specified parameters
sub arraytype {
    my ($pref, $cfield, $dfield) = @_;

    if ($cfield->[1] =~ /^(c_ubyte|c_uint(8|16|32))$/) {
	my $csize = $2 || "8";
	return "$pref$csize($dfield->[1])";
    } else {
	die "Unsupported array counter type: $cfield->[0]";
    }
}

    die "Unknown field type: $ftype";
}

# Reads and parses the manual page for a given message type
sub readman {
    my ($name) = @_;
    (my $base = $name) =~ s/^[TR]//;
    my $man = "$dir/man9/$base.9p";

    # Open the manual page stream using 'man' program
    open MAN, "man \"$man\" | col -b |" or die "$!\nUnable to open file: $man";

    my $line;

    # Search for the NAME section
    while ($line !~ /^NAME/) {$line = <MAN> or last }
    die "NAME section not found in the manual page $man" unless $line =~ /^NAME/;

    # Parse the NAME section
    my $desc = "";
    while ($line = <MAN>) {
	last if $line =~ /^[A-Z]/;
	last if $desc and $line =~ /^\s*$/;
	if ($desc || $line =~ /^\s+([^\s,-]+(,\s*[^\s,-]+)*)\s+-+\s+(.*)$/ && grep {$_ eq $base} split(/,\s*/, $1)) {
	    if (not $desc) {
		$desc = "\u$1";
	    } else {
		$desc = $desc."\n$1";
	    }
	}
    }
    die "Short description of $base not found in the NAME section of $man" unless $desc;

    # Search for the SYNOPSIS section
    while ($line !~ /^SYNOPSIS/) { $line = <MAN> or last }
    die "SYNOPSIS section not found in the manual page $man" unless $line =~ /^SYNOPSIS/;

    # Parse the SYNOPSIS section
    my @struct = ();
    while ($line = <MAN>) {
	last if $line =~ /^[A-Z]/;
	# Test for the structure definition
	if ($line =~ /^\s+([^\s[(*]+(\[[^]]+\]|\*\([^)]+\))\s+)+([^\s\[\]\(\)*]+)\s*/) {
	    last if @struct and $3 and $3 ne $name;
	    if (!$3 && @struct || $3 eq $name) {
		# Parse the structure definition
		my @strdef = split(/\s+/, $line);
		my ($fname, $ftype);
		foreach my $field (@strdef) {
		    next if not $field;
		    # The message type field
		    if ($field =~ /^([^\s[(*]+)$/) {
			$fname = "type";
			$ftype = "c_ubyte";
		    # A constant length field or a string
		    } elsif ($field =~ /^([^\s[(*]+)\[(\d+|s|n)\]$/) {
			$fname = $1;
			$ftype = fieldtype($fname, $2);
		    # A variable length byte field
		    } elsif ($field =~ /^([^\s[(*]+)\[([^\]]+)\]$/) {
			$fname = $1;
			if ($struct[@struct - 1]->[0] eq "$2") {
			    $struct[@struct - 1] = [$fname, arraytype("p9msgarray", $struct[@struct - 1], [$fname, "c_ubyte"])];
			    warn "$name: -$2, + $1: $struct[@struct - 1]->[1]";
			    next;
			} else {
			    my @counters = grep { $_->[0] eq "$2" } @struct or die "Counter field not found: $2";
			    $ftype = arraytype("p9msgparray", @counters[0], [$fname, "c_ubyte"]);
			}
		    # A variable length compound field
		    } elsif ($field =~ /^([^\s[(*]+)\*\(([^\s[]+)\[([^\]]+)\]\)$/) {
			$fname = $2;
			if ($struct[@struct - 1]->[0] eq "$1") {
			    $struct[@struct - 1] = [$fname, arraytype("p9msgarray", $struct[@struct - 1], [$fname, fieldtype($fname, $3)])];
			    warn "$name: -$1, + $2: $struct[@struct - 1]->[1]";
			    next;
			} else {
			    my @counters = grep { $_->[0] eq "$1" } @struct or die "Counter field not found: $1";
			    $ftype = arraytype("p9msgparray", @counters[0], [$fname, fieldtype($fname, $3)]);
			}
		    # Error: unable to parse the field description
		    } else {
			die "Unable to parse the field description: $field";
		    }
		    push(@struct, [$fname, $ftype]);
		    warn "$name: + $fname: $ftype";
		}
	    }
	}
    }

    close(MAN);

    return ($desc, \@struct);
}

# Read in enum items
my %types = ();
my $ord = 0;
my $Tmax = $ord;
while ($line = <STDIN>) {
    if ($line =~ /^\s*([TR]([^\s=,]+))(\s*=\s*(\d+))?\s*,?\s*(\/\*\s*(.*)\s*\*\/)?$/) {
	$Tmax = $ord unless $ord < $Tmax;
	if ($1 ne "Tmax") {
	    my $base = $2;
	    $ord = $4 if $3;
	    my $type = { ord => $ord, name => $1, comment => $6 };
	    ($type->{desc}, $type->{struct}) = readman($type->{name});
	    $types{$base} = { ord => $ord } unless $types{$base};

	    $types{$base}->{T} = $type if $type->{name} =~ /^T/;
	    $types{$base}->{R} = $type if $type->{name} =~ /^R/;
	    warn "Add type '$type->{name}'";
	}
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
