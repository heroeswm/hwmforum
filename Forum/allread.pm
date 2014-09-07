package Forum::allread;
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
my $fid = int(param('id'));
my $page = int(param('page'));
if ($fid == 0) {
	print redirect('forum.pl');
	exit;
}

our $dbh = connect_db();
my %login = get_login($dbh);
if (!$login{id} || param('chk') != gen_crc($login{sid}, 'allread'.$fid)) {
	print redirect('forum.pl');
	exit;
}

my $forum = $dbh->selectrow_hashref('SELECT topics,msgs FROM ::forums WHERE fid=? LIMIT 1', undef, $fid);
my $lasttid = $dbh->selectrow_array('SELECT tid FROM ::threads WHERE fid=? ORDER BY tid DESC LIMIT 1', undef, $fid);
$dbh->do("UPDATE ::lastfread SET topics=?,msgs=?,lasttid=? WHERE uid=? AND fid=?", undef, $forum->{topics}, $forum->{msgs}, $lasttid, $login{id}, $fid);
$dbh->do("DELETE FROM ::lastread WHERE uid=? AND tid IN (SELECT tid FROM `::threads` WHERE fid=?)", undef, $login{id}, $fid);

print redirect('forum_thread.pl?id='.$fid.($page?'&page='.$page:''));
$dbh->disconnect();
}
