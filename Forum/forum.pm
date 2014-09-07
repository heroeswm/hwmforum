package Forum::forum;
use strict;
use utf8;
use DBI;
use CGI qw/-utf8 :standard/;
use POSIX;
use Forum::Func;
use Forum::Adds;
use base 'Exporter';

our @EXPORT_OK = qw(main);

sub main
{
	print header(
		-type => 'text/html',
		-charset => 'UTF-8',
	);
	print_start_html('');

	our $dbh = connect_db();

	if (cHWM()) {
		print '<div class="desc desc_logo">HeroesWM Forum Alt-UP (альтернативный апгрейд форума ГВД)</div>';
	} else {
		print '<div class="desc desc_logo">Форум&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;<span id="smile">0_o</smile></div>';
		print '<script language="javascript">var cc=0;setInterval(function() {
			var arr = ["0_o", "o_o", "o_0", "o_o"];
			$("#smile").html(arr[cc++%4]);
		}, 1000)</script>';
	}

	my %login = get_login($dbh);
	if ($login{id} && $login{nick}) {
		printf '<div class="desc desc_auth" style="display:inline-block; text-align:right; width:48%">Вы вошли как %s (<a href="settings.pl">Настройки</a>, <a href="logout.pl?chk='.encode_entities(gen_crc($login{sid}, 'logout')).'">Выйти</a>)</div>', encode_entities($login{nick});
	} else {
		print '<div class="desc desc_auth" style="display:inline-block; text-align:right; width:48%">Вы не авторизованы (<a href="login.pl">Войти</a>)</div>';
	}
	print '<table class="mt">
			<tr class="toptr">
				<th width="30">&nbsp;</th>
				<th width="45%">Список форумов</th>
				<th width="50%">Последняя тема</th>
				<th width="5%">Всего</th>
			</tr>';

	my $num = 0;
	my $oldcat = undef;
	foreach (@{$dbh->selectall_arrayref('SELECT f.fid, f.name, f.desc, f.msgs, t.tid, t.topic, u.nick, UNIX_TIMESTAMP(m.date), c.catid, c.name, f.topics, l.topics, l.msgs, f.dtopics, f.dmsgs FROM ((::forums as f LEFT JOIN ((::threads as t LEFT JOIN ::msgs as m ON t.last=m.id) LEFT JOIN ::users as u ON u.id='.(settings('show_author') eq 'first'?'t':'m').'.author) ON f.last=t.tid) LEFT JOIN ::categories as c USING(catid)) LEFT JOIN ::lastfread as l ON l.fid=f.fid AND l.uid=? ORDER BY c.weight, f.weight', undef, $login{id})}) 
	{
		my ($fid, $name, $desc, $msgs, $tid, $topic, $author, $date, $catid, $catname, $topics, $readtopics, $readmsgs, $dtopics, $dmsgs) = @$_;
		next if (not allowed_to('view', $fid, $login{acl}));
		
		if ($oldcat != $catid) {
			print '<tr class="fgrps"><td colspan=4>'.encode_entities($catname).'</td></tr>';
			$num = 0;
			$oldcat = $catid;
		}

		my $class = $num++ % 2 ? 'c2' : 'c1';
		print '<tr class="'.$class.'">';
		print '<td class="br vlmid">';
		if ($login{id} && $readtopics != $topics) {
			print '<div class="nf_newtopics">+</div>';
		} elsif ($login{id} && $readmsgs != $msgs) {
			print '<div class="nf_newmsgs">+</div>';
		} else {
			print '<div class="nf_nonewmsgs">&nbsp;</div>';
		}
		print '</td>';
		print '<td class="br"><a class="ft" href="forum_thread.pl?id='.$fid.'">'.encode_entities($name).'</a><br>'.encode_entities($desc).'</td>';
		print '<td class="br">'.($tid?'<a class="ft" href="forum_messages.pl?id='.$tid.'">'.encode_entities($topic).'</a><br>Автор: '.link_to_pers($author).', '.strftime("%d.%m, %H:%M", localtime $date).' <a href="forum_messages.pl?id='.$tid.'&page=last">&raquo;</a>':'').'</td>';
		print '<td align="center">'.($topics-$dtopics).'<br><small>('.($msgs-$dmsgs).')</small></td>';
		print '</tr>';
	}
	print '<tr class="footertr"><td colspan=4></td></tr>';
	print '</table>';

	$dbh->disconnect();
	print end_html();
}
