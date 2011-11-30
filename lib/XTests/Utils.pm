#===============================================================================
#
#         FILE:  Xtests/Utils.pm
#
#  DESCRIPTION:  
#
#       AUTHOR:  ryg
#      COMPANY:  Xyratex 
#      CREATED:  09/05/2011 03:55:22 PM
#===============================================================================
package XTests::Utils;
use strict;
use warnings;

use LWP;
use Carp;
use Log::Log4perl qw(:easy);
use Cwd qw(chdir);
use File::chdir;
use File::Path;
use File::Find;
use Data::Dumper;

our @ISA = ("Exporter");
our @EXPORT = qw(&trim &runEx &parseIEFile &compareIE &getExecutedTestsFromWD);

sub trim{
   my $string = shift;
   if(defined( $string)){
        $string =~ s/^\s+|\s+$//g;
   }
   return $string;
}


sub runEx{
    my ($cmd, $dieOnFail,$failMess ) = @_;    
    DEBUG "Cmd is [$cmd]";
    DEBUG "WD  is [$CWD]";

    $dieOnFail = 0 if ( !( defined $dieOnFail ) );

    my $error_code = system($cmd);

    if ( ( $error_code != 0 ) and ( $dieOnFail == 1 ) ) {
        confess "Child process failed with error status $error_code";
    }

    INFO "Return code is:[" . $error_code . "]";
    return $error_code;
}

sub parseIEFile{
    my $file = shift;
    open(F,"< $file") or confess "Cannot open file: $file";
    my @onlyvalues;
    while(<F>){
        my $str=$_;
        chomp $str;
        my @nocomment = split (/#/,$str);
        next unless defined $nocomment[0];
        $nocomment[0] = trim( $nocomment[0]) if defined $nocomment[0];
        confess "Cannot parse file, space found on string [$str]:[".$nocomment[0]."]" 
            if $nocomment[0] =~ m/\s+/ ;
        push(@onlyvalues, $nocomment[0]) if $nocomment[0] ne '';
    }
    close F;
    return \@onlyvalues;
}

sub compareIE{
    my ($template, $value) =@_;
    $template = trim $template;
    #DEBUG "Compare for exclusion: [$template] and [$value]";
    if($template =~ m/\*$/){
        $template =~ s/\*//;
        return 2 if( $value =~ m/^$template.*/);
    }else{
        return 1 if( $value =~ m/^$template$/);
    }
    return 0;
}


sub  getExecutedTestsFromWD{
    my $wd = shift;
    my @testlist;
    return \@testlist  unless -d $wd;
    find sub {
        my $file = $_;
        my $path =  $File::Find::name;
        $path =~ s/^$wd//;
        $path =~ s/^\///;
        push (@testlist, $path) unless ( -d $file); }, 
        $wd; 
    #DEBUG Dumper \@testlist;
    return \@testlist;
}

1;

