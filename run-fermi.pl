#!/usr/bin/env perl

use strict;
use warnings;
use Getopt::Std;

&main;

sub main {
	my %opts = (e=>'fermi', t=>2, p=>'fmdef', f=>17, k=>50);
	getopts('e:t:p:Pcf:', \%opts);

	die(qq/Usage: run-fermi.pl [options] <in1.fq> [in2.fq [...]]\n/) if (@ARGV == 0);

	my (@lines, $in_list, $fqs);

	push(@lines, "FERMI=$opts{e}", "FLTUNIQ_K=$opts{f}", "UNITIG_K=$opts{k}", "");
	push(@lines, "all:$opts{p}.msg.gz", "");

	$in_list = join(" ", @ARGV);

	$fqs = '';
	if (defined($opts{P}) && !defined($opts{c})) {
		die if (@ARGV % 2 != 0);
		$fqs = '';
		for (my $i = 0; $i < @ARGV; $i += 2) {
			$fqs .= "\$(FERMI) pe2cofq $ARGV[$i] ".$ARGV[$i+1]."; ";
		}
		$fqs = '(' . $fqs . ')';
	} else {
		for my $f (@ARGV) {
			$fqs .= ($f =~ /\.gz$/)? "gzip -dc $f; " : "cat $f; ";
		}
	}
	chop($fqs);
	$fqs = '(' . $fqs . ')';

	push(@lines, "# Construct the FM-index for raw sequences");
	my @part;
	my $pre = "$opts{p}.raw";
	push(@part, sprintf("$pre.%.4d.fq.gz", $_)) for (0 .. $opts{t}-1);
	push(@lines, join(" ", @part) . ":$in_list");
	push(@lines, "\t$fqs | \$(FERMI) splitfa - $pre $opts{t} 2> $pre.split.log\n");
	&build_fmd(\@lines, $opts{t}, $pre, 1);

	push(@lines, "# Error correction");
	push(@lines, "$opts{p}.ec.fq.gz:$opts{p}.raw.fmd");
	push(@lines, "\t$fqs | \$(FERMI) correct -".(defined($opts{P})? 'p' : '')."t $opts{t} \$< - 2> \$@.log | gzip -1 > \$@\n");

	push(@lines, "# Construct the FM-index for corrected sequences");
	@part = ();
	$pre = "$opts{p}.ec";
	push(@part, sprintf("$pre.%.4d.fq.gz", $_)) for (0 .. $opts{t}-1);
	push(@lines, join(" ", @part).":$opts{p}.ec.fq.gz");
	push(@lines, "\t\$(FERMI) fltuniq -k \$(FLTUNIQ_K) \$< 2> $opts{p}.fltuniq.log | \$(FERMI) splitfa - $pre $opts{t} 2> $pre.split.log\n");
	&build_fmd(\@lines, $opts{t}, $pre, 1);

	if (defined($opts{P})) {
		push(@lines, "# Compute the rank of each sequence");
		push(@lines, "$opts{p}.ec.rank:$opts{p}.ec.fmd");
		push(@lines, "\t\$(FERMI) seqsort -t $opts{t} \$< > \$@ 2> \$@.log\n");

		push(@lines, "# Generate pre-unitigs and construct the FM-index");
		@part = ();
		$pre = "$opts{p}.re";
		push(@part, sprintf("$pre.%.4d.fq.gz", $_)) for (0 .. $opts{t}-1);
		push(@lines, join(" ", @part).":$opts{p}.ec.rank $opts{p}.ec.fmd");
		push(@lines, "\t\$(FERMI) unitig -t $opts{t} -r \$^ 2> $pre.unitig.log | \$(FERMI) splitfa - $pre $opts{t} 2> $pre.split.log\n");
		&build_fmd(\@lines, $opts{t}, $pre, 0);

		push(@lines, "# Generate unitigs");
		push(@lines, "$opts{p}.re.fq.gz:$pre.fmd ".join(" ", @part));
		push(@lines, "\tcat \$^ > \$@; rm -f \$^\n");
		push(@lines, "$opts{p}.msg.gz:$opts{p}.re.fq.gz $opts{p}.re.fmd");
		push(@lines, "\t\$(FERMI) unitig -t $opts{t} -l \$(UNITIG_K) -s \$^ 2> \$@.log | gzip -1 > \$@; rm -f \$<\n");
	} else {
		push(@lines, "# Generate unitigs");
		push(@lines, "$opts{p}.msg.gz:$opts{p}.ec.fmd");
		push(@lines, "\t\$(FERMI) unitig -t $opts{t} -l \$(UNITIG_K) \$< 2> \$@.log | gzip -1 > \$@\n");
	}

	print join("\n", @lines), "\n";
}

sub build_fmd {
	my ($lines, $t, $pre, $rm) = @_;
	$rm = $rm? 'rm -f $^' : '';
	for (0 .. $t-1) {
		my $p = sprintf("$pre.%.4d", $_);
		push(@$lines, "$p.fmd:$p.fq.gz");
		push(@$lines, "\t\$(FERMI) build -fo \$@ \$< 2> \$@.log; $rm");
	}
	push(@$lines, "");
	my @part = ();
	push(@part, sprintf("$pre.%.4d.fmd", $_)) for (0 .. $t-1);
	push(@$lines, "$pre.fmd:".join(" ", @part));
	push(@$lines, "\t\$(FERMI) merge -t $t -fo \$@ \$^ 2> \$@.log; rm -f \$^\n");
}
