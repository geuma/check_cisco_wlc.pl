#!/usr/bin/perl -w
#
# check_cisco_wlc.pl
# Copyright (C) 2013 Stefan Heumader <stefan@heumader.at>
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program. If not, see <http://www.gnu.org/licenses/>.
#

use strict;
use warnings;

use File::Basename;
use Getopt::Long;
use Net::SNMP;

# Main values
my $PROGNAME = basename($0);
my $VERSION = '0.3';
my $TIMEOUT = 5;
my $DEBUG = 0;

# Nagios exit states
my %states = (
	OK       =>  0,
	WARNING  =>  1,
	CRITICAL =>  2,
	UNKNOWN  =>  3,
);

# Nagios state names
my %state_names = (
	0 => 'OK',
	1 => 'WARNING',
	2 => 'CRITICAL',
	3 => 'UNKNOWN',
);

# SNMP Data
my %oids = (
	'temperature' => [ '1.3.6.1.4.1.14179.2.3.1.13.0', ],
	'cpu' => [ '1.3.6.1.4.1.14179.1.1.5.1.0', ],
	'memory' => [ '1.3.6.1.4.1.14179.1.1.5.2.0', '1.3.6.1.4.1.14179.1.1.5.3.0', ],
	'clients' => '1.3.6.1.4.1.14179.2.2.13.1.4',
	'accesspoints' => '1.3.6.1.4.1.14179.2.2.1.1.6',

	'mem_total' => [ '1.3.6.1.4.1.14179.1.1.5.2.0', ],
	'mem_free' => [ '1.3.6.1.4.1.14179.1.1.5.3.0', ],
);

my $o_verb = undef;
my $o_help = undef;
my $o_version = undef;
my $o_host = undef;
my $o_port = 161;
my $o_community = undef;
my $o_timeout = 5;
my $o_warn = undef;
my $o_crit = undef;
my $o_category = undef;

# FUNCTIONS

sub p_version ()
{
	print "$PROGNAME version: $VERSION\n";
}

sub p_usage ()
{
	print "$PROGNAME usage: $0 [-v] -H <host> -C <snmp_community> [-p <port>] -w <warning_level> -c <critical_level> [-t <timeout>] [-V] -x <category>\n";
}

sub p_help ()
{
	print "\n$PROGNAME - SNMP Cisco WLC monitor PlugIn for Nagios in version $VERSION\n";
	print "Copyright (C) 2013 Stefan Heumader <stefan\@heumader.at>\n\n";
	p_usage();
	print <<EOF;

-h, --help
	print this help message
-V, --version
	prints version number of Nagios PlugIn
-v, --verbose
	print extra debug informations
-H, --hostname=HOST
	name or IP address of host to check
-C, --community=COMMUNITY NAME
	community name for the host's SNMP agent
-P, --port=PORT
	SNMP port (default 161)
-w, --warn=INTEGER
	warning threshold
-c, --crit=INTEGER
	critical threshold
-x, --category=STRING
	defines which information should be read, the following categories are available:
		temperature  - temperature
		cpu          - cpu utilization
		memory       - used memory in percent
		clients      - amount of associated clients
		accesspoints - amount of associated accesspoints
EOF
}

sub verbose ($)
{
	my $a = $_[0];
	print "$a\n" if defined($o_verb);
}

sub check_options ()
{
	Getopt::Long::Configure ("bundling");
	GetOptions(
		'v' 	=> \$o_verb,		'verbose'	=> \$o_verb,
		'h' 	=> \$o_help,		'help'		=> \$o_help,
		'V' 	=> \$o_version,		'version'	=> \$o_version,
		'H:s'	=> \$o_host,		'hostname:s'	=> \$o_host,
		'p:i'	=> \$o_port,		'port:i'	=> \$o_port,
		'C:s'	=> \$o_community,	'community:s'	=> \$o_community,
		't:i'   => \$o_timeout,		'timeout:i'	=> \$o_timeout,
		'w:s'	=> \$o_warn,		'warn:s'	=> \$o_warn,
		'c:s'	=> \$o_crit,		'critical:s'	=> \$o_crit,
		'x:s'	=> \$o_category,	'category:s'	=> \$o_category,
	);

	if (defined($o_help))
	{
		p_help();
		exit $states{"UNKNOWN"};
	}

	if (defined($o_version))
	{
		p_version();
		exit $states{"UNKNOWN"};
	}

	unless (defined($o_host))
	{
		print "No host specified!\n";
		p_usage();
		exit $states{"UNKNOWN"};
	}

	unless (defined($o_community))
	{
		print "No community string specified!\n";
		p_usage();
		exit $states{"UNKNOWN"};
	}

	unless (defined($o_category))
	{
		print "No category string specified!\n";
		p_usage();
		exit $states{"UNKNOWN"};
	}

	unless ($o_category =~ /^(temperature|cpu|memory|clients|accesspoints)$/)
	{
		print "Invalid category specified!\n";
		p_usage();
		exit $states{"UNKNOWN"};
	}

	unless (defined($o_warn) && defined($o_crit))
	{
		print "No warning or critical thresholds specified!\n";
		p_usage();
		exit $states{"UNKNOWN"};
	}

	# delete % characters if any
	$o_warn =~ s/\%//g;
	$o_crit =~ s/\%//g;
}

# MAIN

check_options();

if (defined($TIMEOUT))
{
	verbose("Alarm at $TIMEOUT + 5");
	alarm($TIMEOUT+5);
}
else
{
	verbose("No timeout defined!\nAlarm at $o_timeout + 10");
	alarm ($o_timeout+10);
}

# Connect to Host
my ($session, $error) = Net::SNMP->session(
	-hostname => $o_host,
	-version => 2,
	-community => $o_community,
	-port => $o_port,
	-timeout => $o_timeout,
);
unless (defined($session))
{
	print ("ERROR: opening SNMP session: $error\n");
	exit $states{'UNKNOWN'};
}

if ($DEBUG)
{
	my $mask = 0x02;
	$mask = $session->debug([$mask]);
}

my $result = undef;
if ($o_category =~ /^(temperature|cpu|memory)$/)
{
	$result = $session->get_request(
		-varbindlist => $oids{$o_category},
	);
}
else
{
	$result = $session->get_table(
		-baseoid => $oids{$o_category}
	);
}

unless (defined($result))
{
	print "ERROR: ".$session->error()."\n";
	$session->close;
	exit $states{'UNKNOWN'};
}
$session->close;

my $value = 0;
foreach (keys %$result)
{
	verbose("OID: $_, Desc: $$result{$_}");
}

if ($o_category =~ /^(temperature|cpu)$/)
{
	$value = $$result{$oids{$o_category}->[0]};
}
elsif ($o_category =~ /^(memory)$/)
{
	my $mem_total =  $$result{$oids{'mem_total'}->[0]};
	my $mem_free =  $$result{$oids{'mem_free'}->[0]};

	# calc memory_used persentage
	$value = int(($mem_total-$mem_free) / $mem_total * 100);
}
elsif ($o_category =~ /^(clients)$/)
{
	foreach (keys %$result)
	{
		$value += $$result{$_};
	}
}
elsif ($o_category =~ /^(accesspoints)$/)
{
	foreach (keys %$result)
	{
		$value++ if $$result{$_} == 1; # only count the AP if it is associated with WLC
	}
}

my $exit_code = $states{"OK"};
my $state = 'OK';
my $perfdata = '';
if ($o_category =~ /^(accesspoints)$/)
{
	if ($value > $o_warn)
	{
	}
	elsif ($value > $o_crit)
	{
		$exit_code = $states{'WARNING'};
	}
	else
	{
		$exit_code = $states{'CRITICAL'};
	}
}
else
{
	if ($value > $o_crit)
	{
		$exit_code = $states{'CRITICAL'};
		$state = 'CRITICAL';
	}
	elsif ($value > $o_warn)
	{
		$exit_code = $states{'WARNING'};
		$state = 'WARNING';
	}
}
$perfdata = "|$o_category=$value;$o_warn;$o_crit";

print "$o_category $state: $value".$perfdata;
exit $exit_code;
