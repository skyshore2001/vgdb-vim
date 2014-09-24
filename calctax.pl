#!/usr/bin/perl
use strict;
use warnings;

=pod
Perl Example for debugging: Calc personal tax.

Usage:
	calctax 10000
	calctax

Location: Shanghai, China
tax exampt:
PIEE (养老保险) 8%
MIEE (医疗保险) 2%
UIEE (失业保险) 0.5% (since 2013/10)
PHFEE (公积金) 7%
--- total: 17.5%
=cut

my $TAX_EXAMPT_BASE = 3500;
my $TAX_EXAMPT_RATE = 0.175; # PIEE(8%)
my @TAX_RATE = (
	# limit, rate, minus
	# if rateBase <= 1500 then tax = taxable * 0.03 - 0
	[1500, 0.03, 0],
	[4500, 0.1, 105],
	[9000, 0.2, 555],
	[35000, 0.25, 1005],
	[55000, 0.3, 2755],
	[80000, 0.35, 5505],
	[undef, 0.45, 13505]
);

sub tax201109  # ($taxable, $forBonus)
{
	my ($taxable, $forBonus) = @_;
    my ($tax, $rateBase);
	if (!$forBonus) {
        $taxable -= $TAX_EXAMPT_RATE;
        $rateBase = $taxable;
	}
	else {
        $rateBase = $taxable / 12;
	}
    
	my $rate = 0;
	for (@TAX_RATE) {
		if (defined($_->[0]) && $rateBase <= $_->[0]) {
			$rate = $_->[1];
			$tax = $taxable * $rate - $_->[2];
			last;
		}
	}
	($tax, $rate);
}

sub showTax # ($amount, [$forBonus=0])
{
	my ($amount, $forBonus) = @_;
	my $taxable = $amount;
	if (! $forBonus) { 
		$taxable -=  $amount * $TAX_EXAMPT_RATE; 
	}
	my ($tax, $rate) = tax201109($taxable, $forBonus);
	printf "%s $amount: Tax=%.2f (Rate %.2f%%, Act.Rate %.2f%%)\n", ($forBonus? "Bonus": "Salary"), $tax, $rate*100, $tax/$amount*100;
}

if (@ARGV) {
	for (@ARGV) {
		next if /\D/;
		showTax($_);
		showTax($_, 1);
	}
}
else {
	for (3000, 5000, 8000, 10000, 12000, 15000, 18000, 20000, 23000, 25000, 30000)
	{
		showTax($_);
	}

	for (10000, 20000, 30000, 40000, 50000, 60000)
	{
		showTax($_, 'forBonus');
	}
}
