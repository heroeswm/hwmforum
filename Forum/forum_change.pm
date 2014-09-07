package Forum::forum_change;
use strict;
use utf8;
use DBI;
use POSIX;
use CGI qw/-utf8 :standard/;
use Forum::Func;
use base 'Exporter';

our @EXPORT_OK = qw(main);

sub post_message
{
	my ($dbh, $forum, $tid, $login, $msg) = @_;
	my $topic = $dbh->selectrow_arrayref('SELECT fid,msgs FROM ::threads WHERE ::threads.tid=? LIMIT 1', undef, $tid);
	if (!ref $topic) {
		return;
	}
	$dbh->do('INSERT INTO ::msgtext (msgid, content) VALUES (0, ?)', undef, $msg);
	my $cid = $dbh->last_insert_id(undef, undef, undef, undef);
	if ($forum->[1] && $msg ne 'open' && $msg ne 'close') {
		$dbh->do('UPDATE ::msgs SET num=num+1 WHERE num=? AND tid=? LIMIT 1', undef, $topic->[1], $tid);
		$dbh->do('INSERT INTO ::msgs (tid,cid,author,num,service) VALUES (?, ?, ?, ?, 1)', undef, $tid, $cid, $login->{id}, $topic->[1]);
	} else {
		$dbh->do('INSERT INTO ::msgs (tid,cid,author,num,service) VALUES (?, ?, ?, ?, 1)', undef, $tid, $cid, $login->{id}, $topic->[1]+1);
	}
	my $newid = $dbh->last_insert_id(undef, undef, undef, undef);
	$dbh->do('UPDATE ::msgtext SET msgid=? WHERE cid=?', undef, $newid, $cid);
	$dbh->do('UPDATE ::threads SET msgs=msgs+1, last=? WHERE tid=?', undef, $newid, $tid);
	$dbh->do('UPDATE ::forums SET msgs=msgs+1, last=? WHERE fid=?', undef, $tid, $topic->[0]);
}

sub move_topic
{
	my ($dbh, $forum, $tid, $from, $to, $login) = @_;
	my $names = $dbh->selectall_hashref('SELECT fid,name FROM forums WHERE fid=? OR fid=?', ['fid'], undef, $from, $to);
	$dbh->do('UPDATE ::threads SET fid=? WHERE tid=?', undef, $to, $tid);
	my ($last) = $dbh->selectrow_array('SELECT tid FROM ::threads WHERE fid=? ORDER BY last DESC LIMIT 1', undef, $from);
	$dbh->do('UPDATE ::forums SET dtopics=dtopics+1, dmsgs=dmsgs+?, last=? WHERE fid=?', undef, $forum->[6], $last, $from);
	$dbh->do('UPDATE ::forums SET topics=topics+1, msgs=msgs+? WHERE fid=?', undef, $forum->[6], $to);
	post_message($dbh, $forum, $tid, $login, "move\n$from|".$names->{$from}->{name}."\n$to|".$names->{$to}->{name});
}

sub main
{
my $tid = int(param('id'));
my $msgid = int(param('msgid'));
my $page = int(param('page'));
$page = 1 unless($page);
if ($tid == 0) {
	return_smth('forum.pl');
	exit;
}

our $dbh = connect_db();
my %login = get_login($dbh);
if (param('chk') != gen_crc($login{sid}, 'dosmth'.$tid)) {
	return_smth('forum.pl');
	exit;
}

my $forum = $dbh->selectrow_arrayref('SELECT t.fid,FIND_IN_SET("closed",attr),t.author,t.topic,attached,attr,t.msgs FROM ::threads as t WHERE t.tid=? LIMIT 1', undef, $tid);
if (!ref $forum || !allowed_to('view', $forum->[0], $login{acl})) {
	return_smth('forum.pl');
	$dbh->disconnect();
	exit;
}
my @forum = @$forum;
if ($msgid && !ref($dbh->selectrow_arrayref('SELECT id FROM ::msgs WHERE tid=? AND id=? LIMIT 1', undef, $tid, $msgid))) {
	return_smth('forum.pl');
	$dbh->disconnect();
	exit;
}

my $action = param('action');
if ($action eq 'close') {
	if (allowed_to('moderate', $forum->[0], $login{acl}) || ($forum->[2] == $login{id} && $login{id})) {
		if (!$forum->[1]) {
			$dbh->do('UPDATE ::threads SET attr=CONCAT_WS(",",attr,"closed") WHERE tid=? LIMIT 1', undef, $tid);
			post_message($dbh, $forum, $tid, \%login, "close");
		}
		return_smth('forum_messages.pl?id='.$tid.'&page=last');
		$dbh->disconnect();
		exit;
	}
} elsif ($action eq 'open') {
	if (allowed_to('moderate', $forum->[0], $login{acl}) || ($forum->[2] == $login{id} && $login{id} && ($forum->[5] =~ /premium/))) {
		if ($forum->[1]) {
			$dbh->do('UPDATE ::threads SET attr=REPLACE(attr,"closed","") WHERE tid=? LIMIT 1', undef, $tid);
			post_message($dbh, $forum, $tid, \%login, "open");
		}
		return_smth('forum_messages.pl?id='.$tid.'&page=last');
		$dbh->disconnect();
		exit;
	}
} elsif ($action eq 'changetopic') {
	if (allowed_to('moderate', $forum->[0], $login{acl}) || ($forum->[2] == $login{id} && $login{id} && (!$forum->[1] || $forum->[5] =~ /premium/))) {
		my $newtopic = param('newtopic');
		utf8::decode($newtopic);
		$newtopic =~ s/^\s+|\s+$//g;
		if ($newtopic ne $forum->[3]) {
			$dbh->do('UPDATE ::threads SET topic=? WHERE tid=? LIMIT 1', undef, $newtopic, $tid);
			post_message($dbh, $forum, $tid, \%login, "changetopic\n" . $forum->[3] . "\n" . $newtopic);
		}
		return_smth('forum_messages.pl?id='.$tid);
		$dbh->disconnect();
		exit;
	}
} elsif ($action eq 'changeattrs') {
	if (allowed_to('moderate', $forum->[0], $login{acl})) {
		my $new_imp = param('important') ? 1 : 0;
		my $ch_imp = $new_imp != ($forum->[5] =~ /important/ ? 1 : 0);
		my $new_pa = param('premium') ? 1 : 0;
		my $ch_pa = $new_pa != ($forum->[5] =~ /premium/ ? 1 : 0);
		my $new_ro = param('readonly') ? 1 : 0;
		my $ch_ro = $new_ro != ($forum->[5] =~ /readonly/ ? 1 : 0);
		my $new_att = param('attached') ? 1 : 0;
		my $ch_att = $new_att != $forum->[4];
		my $new_attr = $forum->[5];
		if ($ch_imp) {
			$new_attr =~ s/important//g;
			$new_attr .= ',important' if ($new_imp);
		}
		if ($ch_pa) {
			$new_attr =~ s/premium//g;
			$new_attr .= ',premium' if ($new_pa);
		}
		if ($ch_ro) {
			$new_attr =~ s/readonly//g;
			$new_attr .= ',readonly' if ($new_ro);
		}
		if (!$ch_att && !$ch_imp && !$ch_pa && !$ch_ro) {
			return_smth('forum_messages.pl?id='.$tid);
			$dbh->disconnect();
			exit;
		}
		$dbh->do('UPDATE ::threads SET attr=?,attached=? WHERE tid=? LIMIT 1', undef, $new_attr, $new_att, $tid);
		post_message($dbh, $forum, $tid, \%login, "changeattrs\n" . ($ch_imp ? "important $new_imp\n" : '') . ($ch_att ? "attached $new_att\n" : '') . ($ch_pa ? "premium $new_pa\n" : '') . ($ch_ro ? "readonly $new_ro\n" : ''));
		return_smth('forum_messages.pl?id='.$tid);
		$dbh->disconnect();
		exit;
	}
} elsif ($action eq 'delmsg') {
	if ($msgid && allowed_to('moderate', $forum->[0], $login{acl}) || ($forum->[2] == $login{id} && $login{id} && ($forum->[5] =~ /premium/))) {
		my $reason = param('reason');
		$reason =~ s/^\s+|\s+$//;
		$dbh->do('INSERT INTO ::delmsg (msgid,uid,reason) VALUES (?, ?, ?)', undef, $msgid, $login{id}, $reason);
		return_smth('forum_messages.pl?id='.$tid.'&page='.$page);
		$dbh->disconnect();
		exit;
	}
} elsif ($action eq 'banmsg') {
	if ($msgid && allowed_to('moderate', $forum->[0], $login{acl})) {
		my $reason = param('reason');
		$reason =~ s/^\s+|\s+$//;
		my $author = $dbh->selectrow_arrayref('SELECT ::author FROM msgs WHERE id=? LIMIT 1', undef, $msgid);
		if (ref $author) {
			my $time = param('time');
			if ($time <= 0) {
				$dbh->do('INSERT INTO ::bans (msgid, uid, who, onid, type, reason, bantill) VALUES (?, ?, ?, ?, ?, ?, ?)', undef, $msgid, $login{id}, $author->[0], 0, 'justwarn', $reason, undef);
			} else {
				$time *= 3600;
				$time = 168*3600 if ($time > 168*3600);
				$dbh->do('INSERT INTO ::bans (msgid, uid, who, onid, type, reason, bantill) VALUES (?, ?, ?, ?, ?, ?, DATE_ADD(NOW(), INTERVAL ? SECOND))', undef, $msgid, $login{id}, $author->[0], $forum->[0], 'forum', $reason, $time);
			}
		}
		return_smth('forum_messages.pl?id='.$tid.'&page='.$page);
		$dbh->disconnect();
		exit;
	}
} elsif ($action eq 'abuse') {
	if ($msgid && $login{id}) {
		$dbh->do('INSERT INTO ::abuse (msgid,uid,reason) VALUES (?, ?, ?)', undef, $msgid, $login{id}, param('reason'));
		return_smth('forum_messages.pl?id='.$tid.'&page='.$page);
		$dbh->disconnect();
		exit;
	}
} elsif ($action eq 'move') {
	my $dest = int(param('dest'));
	if (allowed_to('moderate', $forum->[0], $login{acl}) && allowed_to('moderate', $dest, $login{acl})) {
		move_topic($dbh, $forum, $tid, $forum->[0], $dest, \%login);
		return_smth('forum_messages.pl?id='.$tid.'&page=last');
		$dbh->disconnect();
		exit;
	}
} elsif ($action eq 'delete') {
	if (allowed_to('moderate', $forum->[0], $login{acl})) {
		move_topic($dbh, $forum, $tid, $forum->[0], 0, \%login);
		return_smth('forum_thread.pl?id='.$forum->[0]);
		$dbh->disconnect();
		exit;
	}
} elsif ($action eq 'vote') {
	my $suf = (param('up') ? 'up' : 'down');
	if (check_limits($dbh, $login{id}, 'votemsg'.$suf, [5, 30, 120])) {
		if ($dbh->do('INSERT IGNORE INTO ::msgvotes (msgid,uid,fid,isup) VALUES (?, ?, ?, ?)', undef, $msgid, $login{id}, $forum->[0], int(param('up')) ? 1 : 0) == 1) {
			$dbh->do('UPDATE ::msgs SET vote'.$suf.'=vote'.$suf.'+1 WHERE id=? LIMIT 1', undef, $msgid);
		}
	}
	my $jsresp;
	if (param('js')) {
		$jsresp = $dbh->selectrow_array('SELECT voteup-votedown FROM ::msgs WHERE id=? LIMIT 1', undef, $msgid);
	}
	return_smth('forum_messages.pl?id='.$tid.'&page='.$page, $jsresp);
	$dbh->disconnect();
	exit;
}
return_smth('forum.pl');
$dbh->disconnect();
}
