package Forum::logout;
use strict;
use utf8;
use DBI;
use CGI qw/-utf8 :standard/;
use CGI::Cookie;
use Forum::Func;
use Forum::Adds;
use base 'Exporter';

our @EXPORT_OK = qw(main);

sub main
{
	my %cookies = fetch CGI::Cookie;
	if (exists $cookies{'sid'}) {
		my $sid = $cookies{'sid'}->value;
		if (gen_crc($sid, 'logout') == param('chk')) {
			our $dbh = connect_db();
			my %login = get_login($dbh);
			if (cHWM || defined $login{nick}) {
				if (cHWM) {
					$dbh->do('DELETE FROM ::logins WHERE sid=?', undef, $sid);
				} else {
					$dbh->do('UPDATE ::users SET sid="" WHERE sid=?', undef, $sid);
				}
				$dbh->disconnect();
				my $cookie = new CGI::Cookie(-name=>'sid', -value=>undef, -expires=>'-1h');
				print header(-status=>'302 Found', -location=>'forum.pl', -cookie=>[$cookie]);
				exit;
			}
		}
	}
	print redirect('forum.pl');
}

