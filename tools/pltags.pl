#!/usr/bin/perl -w
# Perl tags generator that uses the debugger hooks
# Ned Konz <ned@bike-nomad.com>
# $Revision: 1.7 $
# TODO
# * figure out a way to avoid running BEGIN blocks

use strict;
use File::Find;
use Getopt::Std;

sub usage
{
	print <<EOF;
usage: $0 [-R] [-f outfile] [-a] [-L listfile] [file [...]]
-R           recurse into dirs
-f outfile   specify output file (default=tags)
-a           append to output file
-L listfile  get filenames/options from listfile
-h           get this help message
-v           list filenames to stderr
EOF
	exit(shift());
}

# process cmdline options
my %opts;
getopts('Rf:aL:hv', \%opts) || usage(1);
usage(0) if defined($opts{'h'});
my $outfile = defined($opts{'f'}) ? $opts{'f'} : 'tags';
if (defined($opts{'L'}))
{
	open(LFILE, $opts{'L'});
	map { chomp ; unshift(@ARGV, $_) } <LFILE>;
	close(LFILE);
}

# now filenames are in @ARGV
push(@ARGV, '.') if ($#ARGV < 0);

my @files;
my $top;
my $nDirs;

sub wanted {
	-f _ && /^.*\.p[lm]\z/si && push(@files, $File::Find::name);
	$File::Find::prune = !defined($opts{'R'}) && $nDirs > 1;
	-d _ && $nDirs++;
}

# process directories
foreach $top (@ARGV)
{
	$nDirs = 0;
	File::Find::find({wanted => \&wanted}, $top);
}

# Load debugger into environment var $PERL5DB
{
	local $/ = undef;
	my $debugger = <DATA>;
	$debugger =~ s/\s*#.*$//gm;	# get around bugs in PERL5 debugger code
	$debugger =~ s/\s+/ /gms;
	$ENV{PERL5DB} = $debugger;
}

# Clear outfile if not appending
if (!defined($opts{'a'}))
{
	open(OUTFILE,">$outfile") or die "can't open $outfile for write: $!\n";
	close(OUTFILE);
}

# pass output file name in env var
$ENV{PLTAGS_OUTFILE} = ">>$outfile";

# Spawn Perl for each file
foreach my $fileName (map { $_ =~ s{^\./}{}; $_ } @files)
{
	print STDERR "$fileName\n" if $opts{'v'};
	system("$^X -d $fileName");
}

# Perl-only sort -u
open(OUTFILE, $outfile) or die "can't open $outfile for read: $!\n";
my @lines = <OUTFILE>;
close(OUTFILE);
@lines = sort @lines;
open(OUTFILE, ">$outfile") or die "can't open $outfile for write: $!\n";
my $lastLine = '';
print OUTFILE grep { $_ ne $lastLine and $lastLine = $_ } @lines;
close(OUTFILE);

# End of main program; debugger text follows

__DATA__

# remove those annoying error messages
BEGIN { close STDOUT; close STDERR }

sub DB::DB
{
	sub DB::keySort
	{
		my ($aPackage, $aTag) = $a =~ m{(.*)::(\w+)};
		my ($bPackage, $bTag) = $b =~ m{(.*)::(\w+)};
		$aPackage cmp $bPackage
		or $aTag eq 'BEGIN' ? -1 : 0
		or $bTag eq 'BEGIN' ? 1 : 0
		or $aTag cmp $bTag;
	}

	open(PLTAGS_OUTFILE, $ENV{PLTAGS_OUTFILE});

	# from perldebguts:
	# A hash "%DB::sub" is maintained, whose keys are subroutine names and
	# whose values have the form "filename:startline-endline".  "filename" has
	# the form "(eval 34)" for subroutines defined inside "eval"s, or
	# "(re_eval 19)" for those within regex code assertions.

	foreach my $key (sort DB::keySort keys(%DB::sub))
	{
		my ($fileName, $lineNumber) = $DB::sub{$key} =~ m{(.+):(\d+)-\d+};
		my ($package, $tag) = $key =~ m{(.*)::(\w+)};
		next if $package eq 'DB' || $tag =~ /^__ANON__/ || $fileName =~ '^\(\D+\d+\)$';
		my $lines = \@{'main::_<' . $fileName};
		my $line = $$lines[$lineNumber];
		# back up to a recognizable line
		while ($lineNumber > 1
			and (($tag eq 'BEGIN' and $line !~ m{\bpackage\s+} )
			or ($tag ne 'main' and $tag ne 'BEGIN' and $line !~ m{\b$tag\b} )))
		{
				$lineNumber--;
				$line = $$lines[$lineNumber];
				redo if !$line; # pod lines are undef'd
		}
		chomp($line);
		$line =~ s{[\/^\$]}{\\$&}g;
		$key =~ s/^main:://;	# hide main package name
		$key =~ s/(?:::)?BEGIN$//;
		next if ! $key;
		print PLTAGS_OUTFILE "$key\t$fileName\t/^$line\$/\n";
	}
	exit;
}