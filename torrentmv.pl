#!/usr/bin/perl

use strict;
use warnings;
use Data::Dumper;
use Digest::SHA qw/sha1/;
use File::Find;
use POSIX qw/ceil floor/;

use File::Path qw/mkpath/;

if ( scalar @ARGV < 2 ) { print_help(); }

my $file_name = shift;
my $dir_name  = shift;

if ( not -d $dir_name )  { print_help(); }
if ( not -f $file_name ) { print_help(); }

$/ = undef;
open my $file, "<", $file_name;
my $bdata = <$file>;
close $file;

my $dict = bdecode($bdata);

$dir_name =~ s/\/$//xmsi;

if ( not defined $dict->{info} or not defined $dict->{info}{files} ) {
    print "Invalif torrent file\n";
    print_help();
}

my $file_list    = $dict->{info}{files};
my $piece_length = $dict->{info}{"piece length"};
my $pieces       = $dict->{info}{pieces};
my $index        = 0;
my $list_length  = scalar @{$file_list};

my @matches;

while ( $index < $list_length ) {
    find( { wanted => \&wanted, no_chdir => 1}, $dir_name );
    if ( scalar @matches == 0 ) {
        printf( "%s not found in directory (size)\n",
            join( "/", @{ $file_list->[$index]{path} } ) );
    }
    else {
        my $matched = sha_find(@matches);
        if ( not defined $matched ) {
            printf( "%s not found in directory (hash)\n",
                join( "/", @{ $file_list->[$index]{path} } ) );
        }
        else {
            printf( "%s matched against %s\n",
                join( "/", @{ $file_list->[$index]{path} } ), $matched );
            my @path = @{ $file_list->[$index]{path} };
            my $dir = join( "/", @path[ 0 .. scalar @path - 2 ] );
		my $target_dir = "$dir_name\/$dir";
		mkpath $target_dir;
		rename $matched, "$target_dir\/".$path[-1] or die $!;
		print $matched, " --> $target_dir\/".$path[-1], "\n";
        }
    }
    @matches = ();
    $index++;
}

sub file_piece_offset {
    my ($file_index) = @_;
    my $full_size = 0;
    for ( my $i = 0 ; $i < $file_index ; $i++ ) {
        $full_size += $file_list->[$i]{length};
    }
    my $piece_offset = ceil( $full_size / $piece_length );
    my $full_offset  = $piece_offset * $piece_length;
    return ( $full_offset - $full_size, $piece_offset );
}

sub sha_at_offset {
    my ( $file, $offset, $length ) = @_;

    my ( $buf, $data, $read );
    open my $fh, "<", $file or die $!;
    binmode $fh;
    seek( $fh, $offset, 0 ) or die $!;
    $read = read( $fh, $buf, $length ) or die $!;
    if ( $length != $read ) {
        die("You should have implemented a proper read function you idiot!");
    }
    close $fh;
    return sha1($buf);
}

sub sha_find {
    my (@files) = @_;
    my ( $file_offset, $piece_offset ) = file_piece_offset($index);
    foreach my $f (@files) {
        my $sha1 = substr( $pieces, $piece_offset * 20, 20 );
        my $sha2 = sha_at_offset( $f, $file_offset, $piece_length );
        if ( $sha1 eq $sha2 ) {
            return $f;
        }
    }
    return undef;
}

sub wanted {
    if ( -f $File::Find::name ) {
        if ( -s $File::Find::name == $file_list->[$index]{length} ) {
            push @matches, $File::Find::name;
        }
    }
}

sub print_help {
    print "This script takes a torrent file and a directory as input\n";
    print
"and tries to rename files in the directory to match the\n filenames in the torrent\n";
    print "Usage: ./torrentmv.pl <file.torrent> <directory>\n";
	exit();
}

sub bdecode {
    my $string = shift;
    my @chunks = split( //, $string );
    my $root   = _dechunk( \@chunks );
    return $root;
}

sub _dechunk {
    my $chunks = shift;

    my $item = shift( @{$chunks} );
    if ( $item eq 'd' ) {
        $item = shift( @{$chunks} );
        my %hash;
        while ( $item ne 'e' ) {
            unshift( @{$chunks}, $item );
            my $key = _dechunk($chunks);
            $hash{$key} = _dechunk($chunks);
            $item = shift( @{$chunks} );
        }
        return \%hash;
    }
    if ( $item eq 'l' ) {
        $item = shift( @{$chunks} );
        my @list;
        while ( $item ne 'e' ) {
            unshift( @{$chunks}, $item );
            push( @list, _dechunk($chunks) );
            $item = shift( @{$chunks} );
        }
        return \@list;
    }
    if ( $item eq 'i' ) {
        my $num;
        $item = shift( @{$chunks} );
        while ( $item ne 'e' ) {
            $num .= $item;
            $item = shift( @{$chunks} );
        }
        return $num;
    }
    if ( $item =~ /\d/ ) {
        my $num;
        while ( $item =~ /\d/ ) {
            $num .= $item;
            $item = shift( @{$chunks} );
        }
        my $line = '';
        for ( 1 .. $num ) {
            $line .= shift( @{$chunks} );
        }
        return $line;
    }
    return $chunks;
}

