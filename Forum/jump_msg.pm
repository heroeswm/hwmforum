package Forum::jump_msg;
use strict;
use utf8;
use DBI;
use POSIX;
use CGI qw/-utf8 :standard/;
use Forum::Func;
use base 'Exporter';

our @EXPORT_OK = qw(main);

sub main
{
my $msgid = int(param('id'));
our $dbh = connect_db();
my %login = get_login($dbh);

my ($tid, $num, $fid) = $dbh->selectrow_array('SELECT msgs.tid, num, fid FROM msgs INNER JOIN threads ON msgs.tid=threads.tid WHERE id=?', undef, $msgid);
warn ("$tid, $num, $fid");
if (!$tid || !allowed_to('view', $fid, $login{acl})) {
	print redirect('forum.pl');
	$dbh->disconnect();
	exit;
}

print redirect('forum_messages.pl?id='.$tid.'&page='.ceil($num/20).'#'.$msgid);
$dbh->disconnect();
}
