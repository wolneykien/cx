#!/usr/bin/perl

use strict;
use locale;

# Look around
(my $dir = $0) =~ s,/[^/]+$,,;

my $line;

# Search for the protocol version
my $p9ver;
while ($line = <STDIN>) {
    if ($line =~ /^#define\s+VERSION9P\s+"([^"]+)"/) {
	$p9ver = $1;
	last;
    }
}
$p9ver or die "Unable to find the protocol version";

# Search for enum
while ($line !~ /^\s*enum/) { $line = <STDIN> or last; }
while ($line !~ /{/) { $line = <STDIN> or last; }

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
	} elsif ($ftype eq "8") {
	    return "c_uint64";
	} elsif ($ftype eq "13") {
	    return "p9qid";
	} else {
	    return "(c_ubyte * $ftype)";
	}
    } elsif ($ftype eq "s") {
	return "p9msgstring";
    } elsif ($ftype eq "n") {
	return "p9msgarray";
    }
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
	$line =~ s/^\s+//;
	$line =~ s/\s+$//;
	if ($desc || $line =~ /^([^\s,-]+(,\s*[^\s,-]+)*)\s+-+\s+(.*)$/ && grep {$_ eq $base} split(/,\s*/, $1)) {
	    if (not $desc) {
		$desc = "\u$line";
	    } else {
		$desc = $desc."\n$line";
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
			my @counters = grep { $_->[0] eq "$2" } @struct or die "Counter field not found: $2";
			$ftype = fieldtype($fname, $2);
		    # A variable length compound field
		    } elsif ($field =~ /^([^\s[(*]+)\*\(([^\s[]+)\[([^\]]+)\]\)$/) {
			$fname = $2;
			my @counters = grep { $_->[0] eq "$1" } @struct or die "Counter field not found: $1";
			$ftype = "(".fieldtype($fname, $3)." * $1)";
		    # Error: unable to parse the field description
		    } else {
			die "Unable to parse the field description: $field";
		    }
		    push(@struct, [$fname, $ftype]);
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
	    ($types{$base}->{desc}, $type->{struct}) = readman($type->{name});
	    $types{$base} = { ord => $ord } unless $types{$base};

	    $types{$base}->{T} = $type if $type->{name} =~ /^T/;
	    $types{$base}->{R} = $type if $type->{name} =~ /^R/;
	    warn "Add type '$type->{name}'";
	}
    }
    last if $line =~ /}/;
    $ord++;
}

# Returns the structure body and tail
sub get_struct_tail {
    my ($header, $struct) = @_;
    my @hcopy = (@$header);
    my @scopy = (@$struct);

    while (@hcopy and
	   @scopy and
	   join(", ", @{$scopy[0]}) eq join(", ", @{$hcopy[0]})) {
	shift @hcopy;
	shift @scopy;
    }

    my @body = ();
    while (@scopy and
	   $scopy[0]->[1] !~ /^\(p9msg[^*\s]+\s*\*\s*\S+\)$/ and
	   $scopy[0]->[1] !~ /^p9msg\S+$/) {
	push(@body, shift @scopy);
    }

    my @tail = ();
    my @static_tail = ();
    while (@scopy) {
	if ($scopy[0]->[1] =~ /^\(p9msg[^*\s]+\s*\*\s*\S+\)$/) {
	    push(@tail, shift @scopy);
	} elsif ($scopy[0]->[1] =~ /^(p9msg\S+)$/) {
	    push(@tail, [$scopy[0]->[0], "($1 * 1)"]); shift @scopy;
	} else {
	    push(@tail, ["self.tail", "(self.tail * 1)"]);
	    last;
	}
    }

    return (\@body, \@tail, \@scopy);
}

# Prints the message field structure
sub print_struct {
    my ($struct, $indent) = @_;

    print "$indent"."    _pack_ = 1\n";
    print "$indent"."    _fields_ = [\n";
    print "$indent"."        ".join("$indent"."        ", map { "(\"$_->[0]\", $_->[1]),\n" } @$struct);
    print "$indent"."    ]\n";
}

# Prints the cdarclass definition for a complex array type
sub print_cdarclass {
    my ($tail, $indent) = @_;

    print "\n";
    if (@$tail == 1) {
	print "$indent"."    def cdarclass (self):\n".
	      "$indent"."        \"\"\"\n".
              "$indent"."        Returns the type of the message tail \`\`$tail->[0]->[0]\`\`\n".
              "$indent"."        \"\"\"\n";
	$tail->[0]->[1] =~ /\(([^*\s]+)\s*\*\s*\S+\)/ or die "Illegal complex array type notation: $tail->[0]->[1]";
	print "$indent"."        return $1\n";
    } elsif (@$tail > 1) {
	print "$indent"."    def cdarclass (self, index = 0):\n".
	      "$indent"."        \"\"\"\n".
	      "$indent"."        Returns the type of the message tail number \`\`index\`\`:\n";
	my @typelist = ();
	foreach my $type (@$tail) {
	    $type->[1] =~ /^\(([^*\s]+)\s*\*\s*\S+\)$/ or die "Illegal complex array type notation: $type->[1]";
	    push (@typelist, $1);
	}
	print "$indent"."          ".join(";\n$indent          ", map { "* \`\`$_\`\`" } @typelist).".\n".
	      "$indent"."        \"\"\"\n";
	my @counters = ();
	foreach my $type (@$tail) {
	    $type->[1] =~ /\(([^*\s]+)\s*\*\s*(\S+)\)/ or die "Illegal complex array type notation: $type->[1]";
	    my ($eltype, $counter) = ($1, $2);
	    if (@counters) {
		print "$indent"."        if (index - ".join(" - ", @counters).") < $counter:\n";
	    } else {
		print "$indent"."        if index < $counter:\n";
	    }
	    print "$indent"."            return $eltype\n";
	    push(@counters, $counter);
	}
	print "$indent"."        raise IndexError(\"Array index out of bounds\")\n";
    }
}

# Prints the T- or R-message class definition for a given type
sub print_tr {
    my ($header, $type, $desc, $indent) = @_;
    (my $base = $type->{name}) =~ s/^[TR]//;
    my ($body, $tail, $static_tail) = get_struct_tail($header, $type->{struct});

    print "$indent"."class $type->{name} (Structure):\n".
          "$indent"."    \"\"\"\n";
    if ($type->{ord}) {
	print "$indent"."    9P type $type->{ord} '$base' request (transmit) message class\n" if $type->{name} =~ /^T/;
	print "$indent"."    9P type $type->{ord} '$base' reply (return) message class\n" if $type->{name} =~ /^R/;
    }
    print "$indent"."    ".join('\n    ', split(/\n/, $desc))."\n";
    print "$indent"."    Comment: $type->{comment}\n" if $type->{comment};
    print "$indent"."    \"\"\"\n";
    print_struct ($body, $indent) if @$body;
    if (@$static_tail) {
	print "\n";
	print_tr ([],
		  { name => "tail",
		    struct => $static_tail },
		  "The static tail of the outer message class.",
	          "$indent"."    ");
    }
    print_cdarclass($tail, $indent) if @$tail;
}

# Print a common message header definition
sub print_header {
    my ($struct, $name, $desc) = @_;

    print "class $name (Structure):\n".
          "    \"\"\"\n";
    print "    ".join('\n    ', split(/\n/, $desc))."\n";
    print "    \"\"\"\n";
    print_struct (@$struct);
    print "    ]\n\n";
}

# Calculates the common base structure (message header)
sub get_common_base {
    my (@allstruct) = @_;

    if (@allstruct) {
	my @msgheader = @{shift @allstruct};

	if (@msgheader) {
	    foreach my $struct (@allstruct) {
		my @newheader = ();
		my @structcopy = (@$struct);
		my $sfield = shift @structcopy;
		my $hfield = shift @msgheader;

		while ($sfield and
		       $hfield and
		       join(", ", @$sfield) eq join(", ", @$hfield)) {
		    push(@newheader, $hfield);
		    $sfield = shift @structcopy;
		    $hfield = shift @msgheader;
		}
		@msgheader = @newheader;
	    }
	}
	return @msgheader;
    } else {
	return ();
    }
}

# Calculate the common base structure (message header)
my @msgheader = get_common_base(grep { @$_ } map { ($_->{T}->{struct}, $_->{R}->{struct}) } values %types);
warn "Common base (message header): \n".join("\n", map { "(\"$_->[0]\", $_->[1])" } @msgheader);

# Print out the protocol version
print "# The 9P version implemented\n";
print "VERSION9P = \"$p9ver\"\n\n";

# Print the message header definition
#print_header(\@msgheader, "p9msg", "A 9P message head.");

# Print out the class definitions
my $n = 0;
foreach my $base (sort { $types{$a}->{ord} <=> $types{$b}->{ord}  } keys %types) {
    print "\n" if $n > 0;
    if ($types{$base}->{T} || $types{$base}->{R}) {
	if ($types{$base}->{T}) {
	    print "\n";
	    print_tr(\@msgheader, $types{$base}->{T}, $types{$base}->{desc});
	}
	if ($types{$base}->{R}) {
	    print "\n";
	    print_tr(\@msgheader, $types{$base}->{R}, $types{$base}->{desc});
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
print "# The tuple of all defined message classes\n";
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

print "\n";
print "# Export some constants\n";
print "__all__ += [\"VERSION9P\"]\n";
print "# Export all defined message types\n";
print "__all__ += export_by_prefix(\"T\",globals()) + export_by_prefix(\"R\",globals())\n";
