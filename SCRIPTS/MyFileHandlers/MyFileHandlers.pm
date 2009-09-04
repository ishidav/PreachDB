package MyFileHandlers;

use 5.008;
use strict;
use warnings;
use File::Find;
use File::Spec;


###
# Private data to class MyFileHandlers
###
use vars qw ($MFHmatch_files @MFHmatched_files @MFHfile);

require Exporter;

our @ISA = qw(Exporter);

# Items to export into callers namespace by default. Note: do not export
# names by default without a very good reason. Use EXPORT_OK instead.
# Do not simply export all your public functions/methods/constants.

# This allows declaration	use MyFileHandlers ':all';
# If you do not need this, moving things directly into @EXPORT or @EXPORT_OK
# will save memory.
our %EXPORT_TAGS = ( 'all' => [ qw(
	
) ] );

our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } );

our @EXPORT = qw(
	
);

our $VERSION = '0.01';

# Preloaded methods go here.


######################################
# Class constructor
#
######################################
sub new {
  my $package = shift;
  return bless({}, $package);
}

######################################
# Creates a list of files in dir that
# matches match_files
######################################
sub MFHfind{
    my $self = shift;
    my $dir = shift;
    if (-l $dir){
	my $olddir = $ENV{PWD};
#	print "current directory is $ENV{PWD}\n";
	$MFHmatch_files = shift;
	find({wanted =>\&MFHwanted, follow => 1}, $dir);
#	chdir $olddir  or die "Cannot change to $olddir";
#	print "current directory2 is $ENV{PWD}\n";
    }
    else{
	$MFHmatch_files = shift;
	find(\&MFHwanted,$dir);
    }
}

sub MFHwanted{
    if ($MFHmatch_files eq "") {
	push @MFHmatched_files, $File::Find::name if -s;
    }
    else{
	if($File::Find::name =~ /$MFHmatch_files/) {
	    push @MFHmatched_files, $`.$&;	    
	}
    }
}

######################################
# Returns a list of files found in
# MHFfind
######################################
sub MFHlistoffiles{
    my @matched_files =  @MFHmatched_files;
    #Clear private data
    @MFHmatched_files = (); 
    return @matched_files;
}

######################################
# Open a file, reads it into an array
#
######################################
sub MFHreadfile{
    my $self = shift;
    my $file = shift;
    my $FH;
    print "Reading file $file \n";
    open($FH,"<$file") || die "Error: can not open file $file";
    while (defined(my $line = readline($FH))) {
	push @MFHfile, $line;
    }
    close($FH);
}

######################################
# Returns the current file in MFHfile 
# and resets the array
######################################
sub MFHfile{
    my @file = @MFHfile;
    #Clear private data
    @MFHfile = ();
    return @file;
}

######################################
# Open a file, writing the passed 
# array
######################################
sub MFHwritefile{
    my $self = shift;
    my $filen = shift;
    my $file_ptr = shift;
    my @file = @$file_ptr;
    my $FH;
    print "Writing to file $filen \n";
    open($FH,">$filen") || die "Error: can not open file $filen";
    foreach my $line (@file) {
	print $FH $line;
    }
    close($FH);
}

######################################
# Current Directory
# 
######################################
sub MFHcurdir{
    my $self = shift;
    return $ENV{PWD};
}

######################################
# Concatenate Current directory and
# input param
######################################
sub MFHconcatdir{
    my $self = shift;
    my $curr = shift;
    my $param= shift;
    my $dir = File::Spec->catdir($curr,$param);
    if (-d $dir) {
	return $dir;
    }else{
	die "ERROR: Directory $dir does not exist\n";
    }

}

######################################
# Concatenate Current directory and
# input param
######################################
sub MFHconcatdir2{
    my $self = shift;
    my $curr = shift;
    my $param= shift;
    my $dir = File::Spec->catdir($curr,$param);
    if (-d $dir) {
	print "INFO: Directory $dir already exists\n";
	return $dir;
    }else{
	system("mkdir $dir");	
	return $dir;
    }
}

######################################
# Concatenate Current directory and
# input param
######################################
sub MFHconcatfile{
    my $self = shift;
    my $curr = shift;
    my $param= shift;
    my $filename = File::Spec->catfile($curr,$param);
    if (-s $filename) {
	#print "WARNING: File $filename already exists\n";
	return $filename;
    }else{
	return $filename;
    }
}


######################################
# Generate up to 32-bit pseudo-random 
# number store each bit of this number
# in array
######################################
sub generateRandom32{
    my $upper_bound = shift;
    my @assignment;

    if($upper_bound >= 32) { 
	die "ERROR: Only support 32-bits in generateRandom32 passed value is $upper_bound bits\n";
    }
#
# Roll dice and assign value in binary to binValue
#
    my $roll = int(rand (2**$upper_bound+1));
    my $binValue = sprintf("%b", $roll);

#    print "ub = $upper_bound; roll = $roll; binvalue = $binValue\n";
    
    my $length = length $binValue;
#   print "le = $length; hashvalue =";

#
# Have to zero-extend when assignment is only to a few bits
#
    if($length < ($upper_bound+1)){
	for(my $i = ($length+1); $i <= $upper_bound; $i = $i + 1){
	    push @assignment,  0;
	}
    }
    for(my $i = 0; $i < $length; $i = $i + 1){
	push @assignment,  substr ($binValue, $i, 1);
    }
    

## Debugging info
#    foreach my $i (@assignment){
#	print $i . ",";
#    }
#    print"\n";

    return @assignment;
}

#####################################
#  Flip a fair-coin a number of times,
#  storing each flip in an array
######################################
sub generateRandom{
    my $upper_bound = shift;
    my @assignment;

   my $roll;
#
# Roll dice and assign value in binary to binValue
#
    for(my $i = 0; $i < $upper_bound; $i = $i + 1){
	$roll = int(rand (2));
	push @assignment,  $roll;
    }
    

## Debugging info
#    foreach my $i (@assignment){
#	print $i . ",";
#    }
#    print"\n";

    return @assignment;
}


1;
__END__
# Below is stub documentation for your module. You'd better edit it!

=head1 NAME

MyFileHandlers - Perl extension for blah blah blah

=head1 SYNOPSIS

  use MyFileHandlers;
  blah blah blah

=head1 ABSTRACT

  This should be the abstract for MyFileHandlers.
  The abstract is used when making PPD (Perl Package Description) files.
  If you don't want an ABSTRACT you should also edit Makefile.PL to
  remove the ABSTRACT_FROM option.

=head1 DESCRIPTION

Stub documentation for MyFileHandlers, created by h2xs. It looks like the
author of the extension was negligent enough to leave the stub
unedited.

Blah blah blah.

=head2 EXPORT

None by default.



=head1 SEE ALSO

Mention other useful documentation such as the documentation of
related modules or operating system documentation (such as man pages
in UNIX), or any relevant external documentation such as RFCs or
standards.

If you have a mailing list set up for your module, mention it here.

If you have a web site set up for your module, mention it here.

=head1 AUTHOR

Flavio M de Paula, E<lt>depaulfm@cs.ubc.caE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright 2007 by Flavio M de Paula

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself. 

=cut
