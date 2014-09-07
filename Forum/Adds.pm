package Forum::Adds;
use strict;
use utf8;
use base 'Exporter';
use CGI qw/-utf8 :all/;

our @EXPORT = qw(cPROJID cSPACE cHWM);
our @EXPORT_OK = qw(get_mysql_pass is_premium_mod_default allowed_change_group allowed_to_post);


sub allowed_to_post
{
	my ($def, $fid, $tid, $acl) = @_;
	return $def;
}

sub allowed_change_group
{
	return $_[0] == 5;
}

sub is_premium_mod_default
{
#	return $_[0] == 11;
}

sub get_projid
{
	if (virtual_host() =~ /space/) {
		return 'space';
	}
	my $host = `hostname`;
	if ($host =~ /cancri|rigel|squogre/) {
		return 'home';
	} elsif ($host =~ /^d3/) {
		return 'd3';
	} elsif ($host =~ /kocharin/) {
		return 'vds';
	} elsif ($host =~ /masterhost/) {
		return 'mh';
	}
}

use constant cPROJID => get_projid();
use constant cSPACE => cPROJID eq 'space';
use constant cHWM => !cSPACE;

sub get_mysql_pass
{
	my %passwords = (
		'home' => ['localhost', '3306', 'hwmforum', '<classified>', 'hwmforum'],
		'vds' => ['localhost', '3306', 'hwm_forum', '<classified>', 'hwm_forum'],
		'd3' => ['localhost', '3306', 'hwm_forum', '<classified>', 'hwm_forum'],
		'mh' => ['u220975.mysql.masterhost.ru', '3306', 'u220975', '<classified>', 'u220975_forum'],
		'space' => ['localhost', '3306', 'space', '<classified>', 'space'],
	);
	return @{$passwords{&cPROJID}};
}

