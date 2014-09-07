package Forum::forum_messages;
use strict;
use utf8;
use DBI;
use POSIX;
use CGI qw/-utf8 :standard/;
use Forum::Func;
use Forum::Adds qw(allowed_to_post);
use base 'Exporter';

our @EXPORT_OK = qw(main);

sub main
{

my $tid = int(param('id'));
if ($tid == 0) {
	print redirect('forum.pl');
	exit;
}

our $dbh = connect_db();
my %login = get_login($dbh);

my $forum = $dbh->selectrow_hashref('SELECT f.name,t.fid,t.topic,t.attr,t.author,attached,catid,poll,f.topics,f.msgs FROM ::forums as f JOIN ::threads as t ON f.fid=t.fid WHERE t.tid=? LIMIT 1', undef, $tid);
$forum->{closed} = $forum->{attr} =~ /closed/;
my $premium_mod = $forum->{attr} =~ /premium/ && $forum->{author} == $login{id};
if (!ref $forum || !allowed_to('view', $forum->{fid}, $login{acl})) {
	print redirect('forum.pl');
	$dbh->disconnect();
	exit;
}

my $token = gen_crc($login{sid}, 'dosmth'.$tid);
my @bans = get_bans($dbh, $login{id}, $forum->{catid}, $forum->{fid}, $tid);
my $allow_moder = allowed_to('moderate', $forum->{fid}, $login{acl});
my $allow_post = allowed_to('edit', $forum->{fid}, $login{acl}) && !$forum->{closed} && (($forum->{attr} !~ /readonly/) || ($forum->{author} == $login{id} || $allow_moder)) && !@bans;
$allow_post = allowed_to_post($allow_post, $forum->{fid}, $tid, $login{acl});

my %choices = ();
my %votes = ();
if ($forum->{poll}) {
	%choices = %{$dbh->selectall_hashref('SELECT id, `desc`, `votes` FROM ::poll_vars WHERE tid=?', ['id'], undef, $tid)};
	%votes = %{$dbh->selectall_hashref('SELECT msgid, choice FROM ::poll_votes WHERE tid=?', ['msgid', 'choice'], undef, $tid)};
}

my $postfailreason = '';
if (param('chk') == $token) {
	my $uid = $login{id};
	my $msg = param('msg');
	$msg =~ s/^\s+|\s+$//g;
	my $editmsg = int(param('editmsg'));
	if ($editmsg) {
		my ($author, $date, $service, $delmsg, $banmsg, $num) = $dbh->selectrow_array('SELECT author, UNIX_TIMESTAMP(m.date) as date, service, d.msgid, b.msgid, m.num FROM ((::msgs as m LEFT JOIN ::delmsg as d ON m.id=d.msgid) LEFT JOIN ::bans as b ON m.id=b.msgid) WHERE id=?', undef, $editmsg);
		if (($author != $login{id}) || $service || $delmsg || $banmsg) {
			$postfailreason = 'Вы не можете редактировать это сообщение.';
		} elsif ((abs($date - time()) > 360) && ($num != 1)) {
			$postfailreason = 'Вы можете редактировать сообщения только в течение 5 минут после создания.';
		}
	}
	if ($postfailreason) {
	} elsif (!$editmsg && !$msg && !$forum->{poll}) {
		$postfailreason = 'Вы пытаетесь отправить пустое сообщение.';
	} elsif (!$editmsg && !check_limits($dbh, $uid, 'postmsg', [5, 60, 400])) {
		$postfailreason = 'Вы отправляете слишком много сообщений, подождите немного.';
	} elsif (!$allow_post) {
		$postfailreason = 'Вы не можете оставлять сообщения в этом топике.';
	} elsif (!$editmsg && check_doublepost($dbh, \%login, $msg, $tid)) {
		$postfailreason = 'Ваше последнее сообщение было таким же. Вероятно, даблпост.';
	} elsif ($editmsg) {
		$dbh->do('INSERT INTO ::msgtext (msgid, content) VALUES (?, ?)', undef, $editmsg, $msg);
		my $cid = $dbh->last_insert_id(undef, undef, undef, undef);
		$dbh->do('UPDATE ::msgs SET cid=?, ver=ver+1 WHERE id=?', undef, $cid, $editmsg);
		print redirect('forum_messages.pl?id='.$tid.'&page='.int(param('page')));
		$dbh->disconnect();
		exit;
	} else {
		my $topic = $dbh->selectrow_arrayref('SELECT fid,msgs FROM ::threads as t WHERE t.tid=? LIMIT 1', undef, $tid);
		if (!ref $topic) {
			print redirect('forum.pl');
			$dbh->disconnect();
			exit;
		}
		$dbh->do('INSERT INTO ::msgtext (msgid, content) VALUES (0, ?)', undef, $msg);
		my $cid = $dbh->last_insert_id(undef, undef, undef, undef);
		$dbh->do('INSERT INTO ::msgs (tid,cid,author,num) VALUES (?, ?, ?, ?)', undef, $tid, $cid, $uid, $topic->[1]+1);
		my $newid = $dbh->last_insert_id(undef, undef, undef, undef);
		$dbh->do('UPDATE ::msgtext SET msgid=? WHERE cid=?', undef, $newid, $cid);
		if ($forum->{poll} && allowed_to('poll', $forum->{fid}, $login{acl})) {
			my $vars = $dbh->selectcol_arrayref('SELECT choice FROM poll_votes WHERE tid=? AND uid=?', undef, $tid, $login{id});
			if (ref $vars && @$vars) {
				# ???
			} elsif ($forum->{poll} == 1) {
				if (param('choice') && ref $choices{param('choice')}) {
					$dbh->do('INSERT INTO ::poll_votes (msgid,tid,uid,choice) VALUES (?, ?, ?, ?)', undef, $newid, $tid, $uid, param('choice'));
					$dbh->do('UPDATE ::poll_vars SET votes=votes+1 WHERE tid=? AND id=?', undef, $tid, param('choice'));
				}
			} elsif ($forum->{poll} == 2) {
				foreach (keys %choices) {
					if (param('choice'.$_)) {
						$dbh->do('INSERT INTO ::poll_votes (msgid,tid,uid,choice) VALUES (?, ?, ?, ?)', undef, $newid, $tid, $uid, $_);
						$dbh->do('UPDATE ::poll_vars SET votes=votes+1 WHERE tid=? AND id=?', undef, $tid, $_);
					}
				}
			}
		}
		$dbh->do('UPDATE ::threads SET msgs=msgs+1, last=? WHERE tid=?', undef, $newid, $tid);
		$dbh->do('UPDATE ::forums SET msgs=msgs+1, last=? WHERE fid=?', undef, $tid, $topic->[0]);
		print redirect('forum_messages.pl?id='.$tid.'&page=last');
		$dbh->disconnect();
		exit;
	}
}

print header(
	-type => 'text/html',
	-charset => 'UTF-8',
);
print_start_html('"'.$forum->{topic}.'"');
my $pcount = $dbh->selectrow_array('SELECT COUNT(*) FROM ::msgs WHERE tid=?', undef, $tid);
my $page = get_page($pcount);

print '<script language="javascript">
window.hwmforum = {
	page: '.$page.',
	tid: '.$tid.',
	bbpanel: "'.settings('bbpanel').'",
	token: '.$token.'
};</script>';

print '<div class="path"><a href="forum.pl">Форумы</a> &rarr; <a href="forum_thread.pl?id='.$forum->{fid}.'">'.encode_entities($forum->{name}).'</a> &rarr; <a href="forum_messages.pl?id='.$tid.'">'.encode_entities($forum->{topic}).'</a></div>';
	
my $nav_pages = make_pages_div(ceil($pcount/20), $page, 'forum_messages.pl?id='.$tid.'PAGE_NUMBER');
print '<div align="center">'.$nav_pages.'</div>';

print '<table class="mt">
	<tr class="toptr">
		<th width="20%">Автор</th>';
if (param('action') eq 'edit' && ($allow_moder || ($login{id} == $forum->{author} && $login{id} && (!$forum->{closed} || $premium_mod)))) {
	print '<th width="80%" colspan="2"><div style="display:inline-block;" width="60%"><form method="post" action="forum_change.pl">';
	print '<input type="hidden" name="action" value="changetopic"/>';
	print '<input type="hidden" name="id" value="'.$tid.'"/>';
	print '<input type="hidden" name="chk" value="'.$token.'"/>';
	print '<input type="text" size="60" name="newtopic" value="'.encode_entities($forum->{topic}).'"/> <input type="submit" value="Сохранить"/>';
	print '</form></div>';
	if ($allow_moder) {
		print '<div style="display:inline-block;" width="40%" align="right"><form method="post" action="forum_change.pl">';
		print '<input type="hidden" name="action" value="changeattrs"/>';
		print '<input type="hidden" name="id" value="'.$tid.'"/>';
		print '<input type="hidden" name="chk" value="'.$token.'"/>';
		print '<input type="checkbox" name="attached" '.($forum->{attached}?'checked':'').'/> прикреплено ';
		print '<input type="checkbox" name="important" '.($forum->{attr}=~/important/?'checked':'').'/> важно ';
		print '<input type="checkbox" name="premium" '.($forum->{attr}=~/premium/?'checked':'').'/> п/а ';
		print '<input type="checkbox" name="readonly" '.($forum->{attr}=~/readonly/?'checked':'').'/> r/o ';
		print '<input type="submit" value="Сохранить"/>';
		print '</form></div>';
	}
	print "</th>";
} else {
	print '<th width="80%" colspan="2">'.encode_entities($forum->{topic}).'</th>';
}
print '</tr>';

my $mnum = 0;
my $lastnum = 0;
my $lastiss = 1;

my $editmsg = param('msg');
my $isedit = 0;
my @messages = @{$dbh->selectall_arrayref('SELECT m.id, mt.content, m.ver, UNIX_TIMESTAMP(m.date) as date, num, u1.nick, service, u2.nick, d.reason, u3.nick, b.reason, UNIX_TIMESTAMP(b.bantill) as bantill, b.type, voteup, votedown, mv.isup, pl.clan, pl.lvl, pl.fact, pl.avatar FROM (((((((::msgs as m LEFT JOIN ::msgtext as mt USING(cid)) LEFT JOIN ::users as u1 ON m.author=u1.id) LEFT JOIN ::delmsg as d ON m.id=d.msgid) LEFT JOIN ::users as u2 ON d.uid=u2.id) LEFT JOIN ::bans as b ON m.id=b.msgid) LEFT JOIN ::users as u3 ON b.uid=u3.id) LEFT JOIN ::msgvotes as mv ON mv.msgid=m.id AND mv.uid=?) LEFT JOIN ::plinfo as pl ON u1.id=pl.uid WHERE tid=? ORDER BY m.num ASC LIMIT ?,20', undef, $login{id}, $tid, ($page-1)*20)};
foreach (@messages) {
	my ($msgid, $text, $ver, $date, $num, $author, $service, $delwho, $delreason, $banwho, $banreason, $bantill, $bantype, $voteup, $votedown, $myvote, $clan, $lvl, $fact, $avatar) = @$_;
	$mnum++;
	$lastnum = $num;
	if ((param('editmsg') == $msgid) && !$service && ($author eq $login{nick})) {
		if ((not defined($editmsg)) && ((abs($date - time()) < 360) || ($num == 1)) && !@bans && !$service && !$banwho && !$delwho) {
			$isedit = 1;
			$editmsg = $text;
		}
	}

	if ($text =~ /^close/ && $mnum == $pcount && !$delwho) {
		print '<tr class="openclose"><td'.($lastiss?' class="tb"':'').' colspan=3>Тема закрыта by '.link_to_pers($author).' ('.strftime("%F %T", localtime $date).')</td></tr>';
		$lastiss = 1;
	} else {
		$text = encode_text($text, $service, \%login);
		if (defined $delwho) {
			if ($delwho eq $author) {
				$text = '<span class="modred">[Сообщение удалено автором // '.encode_entities($delreason).']</span>';
			} else {
				$text = '<span class="modred">[Сообщение удалено смотрителем '.link_to_pers($delwho).' // '.encode_entities($delreason).']</span>';
			}
		}
		if ($forum->{poll}) {
			if ($num == 1) {
				$text .= '<br><div class="votelist"><span class="votehdr">-- Варианты выбора: --</span><ol>';
				my $sum = 0;
				foreach (sort {$a <=> $b} keys %choices) {
					$sum += $choices{$_}->{votes};
				}
				$sum++ if ($sum == 0);
				foreach (sort {$a <=> $b} keys %choices) {
					$text .= '<li value="'.$_.'">'.encode_entities($choices{$_}->{desc}).' - '.$choices{$_}->{votes}.' голосов, '.sprintf("%.1f%%", $choices{$_}->{votes}/$sum*100).'</li>';
				}
				$text .= '</ol></div>';
			} elsif (ref $votes{$msgid}) {
				my @vars = sort {$a<=>$b} keys %{$votes{$msgid}};
				$text .= '<br>' if ($text);
				if (@vars == 1) {
					$text .= '<span class="pollres">[Игрок проголосовал за вариант '.$vars[0].' - '.$choices{$vars[0]}->{desc}.']</span>';
				} else {
					$text .= '<span class="pollres">[Игрок проголосовал за варианты '.join(', ', @vars).']</span>';
				}
			}
		}
		if (defined $banwho) {
			if ($bantype eq 'justwarn') {
				$text .= '<br><span class="modred">[Игрок предупреждён смотрителем '.link_to_pers($banwho).' // '.encode_entities($banreason).']</span>';
			} else {
				$text .= '<br><span class="modred">[Игрок забанен смотрителем '.link_to_pers($banwho).' до '.strftime('%F %T', localtime $bantill).' // '.encode_entities($banreason).']</span>';
			}
		}
		
		print '<tr class="m3">';
		print '<td rowspan="2" class="br'.(!$lastiss?' tb':'').'">';
		print '<a href="http://'.settings('hwm_url').'/clan_info.php?id='.$clan.'"><img width="20" border="0" align="absmiddle" height="15" alt="#'.$clan.'" src="http://im.heroeswm.ru/i_clans/l_'.$clan.'.gif"/></a> ' if ($clan && settings('pn_clan') eq 'yes');
		print '<b>'.link_to_pers($author).'</b>';
		print " [$lvl]" if ($lvl && settings('pn_lvl') eq 'yes');
		print ' <img width="15" border="0" align="absmiddle" height="15" src="http://im.heroeswm.ru/i/r'.$fact.'.gif"/>' if ($fact && settings('pn_fact') eq 'yes');
		print '<br/>';
		if (settings('pn_avatar') eq 'yes' && $avatar) {
			print '<div class="avatar"><img src="'.$avatar.'" width=150 height=150/></div>';
		}
		if ($allow_post) {
			print '<a class="quoter" href="#" onclick="return answer_to(\''.encode_entities($author).'\');">[>]</a> <a class="quoter" href="#" onclick="return quote_text();">[ц]</a>';
		}
		print '</td>';
#		print '<td class="m3top'.(!$lastiss?' tb':'').'"><div class="msgnum">&nbsp;'.$num.'&nbsp;</div> <div style="display:inline-block; width:40%;"><span class="date">'.strftime("%F %T", localtime $date).'</span></div><div style="text-align:right; width:55%; display:inline-block;"><span class="date">[удалить] [забанить]</span></div></td>';
		print '<td class="m3top'.(!$lastiss?' tb':'').'"><a href="forum_messages.pl?id='.$tid.'&page='.$page.'#'.$msgid.'" name="'.$msgid.'"><div class="msgnum">&nbsp;'.$num.'&nbsp;</div></a> <a href="msg_history.pl?id='.$msgid.'" class="hlink"><span class="date">'.strftime("%F %T", localtime $date);
		if ($ver == 2) {
			print ' &sup1;';
		} elsif ($ver == 3) {
			print ' &sup2;';
		} elsif ($ver == 4) {
			print ' &sup3;';
		} elsif ($ver > 4) {
			printf " (%d)", $ver-1;
		}
		print '</span></a></td>';
		print '<td class="m3top'.(!$lastiss?' tb':'').'" align="right">';
		if (!$delwho && int(param('delmsg')) == $msgid && ($allow_moder || $premium_mod)) {
			print '<form method="post" action="forum_change.pl">';
			print '<input type="hidden" name="action" value="delmsg"/>';
			print '<input type="hidden" name="page" value="'.$page.'"/>';
			print '<input type="hidden" name="id" value="'.$tid.'"/>';
			print '<input type="hidden" name="msgid" value="'.$msgid.'"/>';
			print '<input type="hidden" name="chk" value="'.$token.'"/>';
			print 'Причина: <input type="text" name="reason"/> <input maxlength="254" type="submit" value="Удалить сообщение"/>';
			print '</form>';
		} elsif (!$banwho && int(param('banmsg')) == $msgid && $allow_moder) {
			print '<form method="post" action="forum_change.pl">';
			print '<input type="hidden" name="action" value="banmsg"/>';
			print '<input type="hidden" name="page" value="'.$page.'"/>';
			print '<input type="hidden" name="id" value="'.$tid.'"/>';
			print '<input type="hidden" name="msgid" value="'.$msgid.'"/>';
			print '<input type="hidden" name="chk" value="'.$token.'"/>';
#			print 'Бан: <select name="type"><option value="1">предупреждение</option><option value="2">на тему</option><option value="3">на подфорум</option><option value="4">на категорию</option><option value="5">глобальный</option></select> ';
			print 'Бан на <input type="text" name="time" size=5/> часов, ';
#			print 'на <input type="text" name="time" size=5/>, ';
			print 'причина: <input type="text" name="reason"/> <input maxlength="254" type="submit" value="Наказать игрока"/>';
			print '</form>';
#		} elsif (!$abuse && int(param('abuse')) == $msgid && $login{id}) {
#			print '<form method="post" action="forum_change.pl">';
#			print '<input type="hidden" name="action" value="abuse"/>';
#			print '<input type="hidden" name="page" value="'.$page.'"/>';
#			print '<input type="hidden" name="id" value="'.$tid.'"/>';
#			print '<input type="hidden" name="msgid" value="'.$msgid.'"/>';
#			print '<input type="hidden" name="chk" value="'.gen_crc($login{sid}, 'abuse'.$tid.'-'.$msgid).'"/>';
#			print 'Причина: <input type="text" name="reason"/> <input maxlength="254" type="submit" value="Сообщить модератору"/>';
#			print '</form>';
		} else {
			if (($author eq $login{nick}) && ((abs($date - time()) < 300) || ($num == 1)) && !@bans && !$service && !$delwho && !$banwho) {
				print ' <a class="moder_button" href="forum_messages.pl?editmsg='.$msgid.'&id='.$tid.'&page='.$page.'#edit">[редактировать]</a>';
			}
			if ($allow_moder || $premium_mod) {
				if (!$delwho && !$service) {
					print ' <a class="moder_button jsdel" msgid="'.$msgid.'" href="forum_messages.pl?delmsg='.$msgid.'&id='.$tid.'&page='.$page.'">[удалить]</a>';
				}
				if ($allow_moder && !$banwho) {
					print ' <a class="moder_button jsban" msgid="'.$msgid.'" href="forum_messages.pl?banmsg='.$msgid.'&id='.$tid.'&page='.$page.'">[забанить]</a>';
				}
			}
#			if (!$abuse && $login{id}) {
#				print ' <a class="moder_button" href="forum_messages.pl?abuse='.$msgid.'&id='.$tid.'&page='.$page.'">[пожаловаться]</a>';
#			}
			if ($login{id}) {
				print ' <div class="msgvote">';
				if (not defined $myvote) {
					print '<a class="msgvote voteup" href="forum_change.pl?id='.$tid.'&action=vote&up=1&msgid='.$msgid.'&page='.$page.'&chk='.$token.'">+</a>';
				}
				print $voteup-$votedown;
				if (not defined $myvote) {
					print '<a class="msgvote votedown" href="forum_change.pl?id='.$tid.'&action=vote&up=0&msgid='.$msgid.'&page='.$page.'&chk='.$token.'">-</a>';
				}
				print '</div>';
			}
		}
		print '</td>';
		print '</tr>';
		print '<tr class="m2text">';
		print '<td colspan="2">'.$text.'</td>';
		print '</tr>';
		$lastiss = 0;
	}
}

if ($login{id}) {
	my $fromstart = $ENV{HTTP_REFERER} =~ m#forum\.pl|/$#;
	my $last_r = $dbh->selectrow_arrayref("SELECT num FROM lastread WHERE uid=? AND tid=?", undef, $login{id}, $tid);
	my $last = ref $last_r ? $last_r->[0] : 0;
	if ($last < $lastnum) {
		$dbh->do("INSERT INTO lastread (uid, tid, num) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE num=GREATEST(num, ?)", undef, $login{id}, $tid, $lastnum, $lastnum);
		if (!$fromstart) {
			if (not ref $last_r) {
				if ($ENV{HTTP_REFERER} =~ /\/forum\.pl/) {
					$dbh->do("UPDATE lastfread SET topics=topics+1, msgs=msgs+? WHERE uid=? AND fid=?", undef, $lastnum-$last, $login{id}, $forum->{fid});
				}
			} else {
				$dbh->do("UPDATE lastfread SET msgs=msgs+? WHERE uid=? AND fid=?", undef, $lastnum-$last, $login{id}, $forum->{fid});
			}
		}
	}
	if ($fromstart) {
		$dbh->do("INSERT INTO lastfread (uid, fid, topics, msgs) VALUES (?, ?, ?, ?) ON DUPLICATE KEY UPDATE topics=?, msgs=?", undef, $login{id}, $forum->{fid}, $forum->{topics}, $forum->{msgs}, $forum->{topics}, $forum->{msgs});
	}
}

if ($allow_moder && param('action') eq 'move') {
	print '<tr class="moderation"><td'.($lastiss?' class="tb"':'').' colspan=3 align="center">';
	my $forums = $dbh->selectall_arrayref('SELECT forums.fid,forums.name FROM forums JOIN categories USING(`catid`) ORDER BY categories.weight, forums.weight');
	if (ref $forums) {
		print '<form method="post" action="forum_change.pl">';
		print '<input type="hidden" name="action" value="move"/>';
		print '<input type="hidden" name="id" value="'.$tid.'"/>';
		print '<input type="hidden" name="chk" value="'.$token.'"/>';
		print 'Форум <select name="dest">';
		print join '', map {
			if (allowed_to('moderate', $_->[0], $login{acl}) && $_->[0] != $forum->{fid}) {
				"<option value=\"".$_->[0]."\">".$_->[1]."</option>";
			} else {
				''
			}
		} @$forums;
		print '</select>';
		print ' <input type="submit" value="Переместить"/>';
		print '</form>';
	}
	print '</td></tr>';
} elsif ($allow_moder && param('action') eq 'delete') {
	print '<tr class="moderation"><td'.($lastiss?' class="tb"':'').' colspan=3 align="center">';
	print '<form method="post" action="forum_change.pl">';
	print '<input type="hidden" name="action" value="delete"/>';
	print '<input type="hidden" name="id" value="'.$tid.'"/>';
	print '<input type="hidden" name="chk" value="'.$token.'"/>';
	print 'Эта тема будет удалена: <input type="submit" value="ok"/>';
	print '</form>';
	print '</td></tr>';
} elsif ($allow_moder) {
	print '<tr class="moderation"><td'.($lastiss?' class="tb"':'').' colspan=3 align="center">';
	print '<table cellpadding=0 cellspacing=0><tr>';
	if ($allow_moder) {
		if (!$forum->{closed}) {
			print '<td style="padding: 0px 20px"><a href="forum_change.pl?action=close&id='.$tid.'&chk='.$token.'">Закрыть</a></td>';
		} else {
			print '<td style="padding: 0px 20px"><a href="forum_change.pl?action=open&id='.$tid.'&chk='.$token.'">Открыть</a></td>';
		}
		print '<td style="padding: 0px 20px"><a href="forum_messages.pl?action=move&id='.$tid.'&page='.$page.'">Переместить</a></td>';
		print '<td style="padding: 0px 20px"><a href="forum_messages.pl?action=delete&id='.$tid.'&page='.$page.'">Удалить</a></td>';
		print '<td style="padding: 0px 20px"><a href="forum_messages.pl?action=edit&id='.$tid.'&page='.$page.'">Редактировать</a></td>';
		#print '<td style="padding: 0px 20px"><a href="forum_change.pl?action=delete&id='.$tid.'&chk='.$token.'">Удалить</a></td>';
	}
	print '</tr></table></td></tr>';
} elsif ($login{id} == $forum->{author} && $login{id} && !$forum->{closed}) {
	print '<tr class="moderation"><td'.($lastiss?' class="tb"':'').' colspan=3 align="center">';
	print '<table cellpadding=0 cellspacing=0><tr>';
	print '<td style="padding: 0px 20px"><a href="forum_change.pl?action=close&id='.$tid.'&chk='.$token.'">Закрыть</a></td>';
	print '<td style="padding: 0px 20px"><a href="forum_messages.pl?action=edit&id='.$tid.'&page='.$page.'">Редактировать</a></td>';
	print '</tr></table></td></tr>';
} elsif ($premium_mod && $forum->{closed}) {
	print '<tr class="moderation"><td'.($lastiss?' class="tb"':'').' colspan=3 align="center">';
	print '<table cellpadding=0 cellspacing=0><tr>';
	print '<td style="padding: 0px 20px"><a href="forum_change.pl?action=open&id='.$tid.'&chk='.$token.'">Открыть</a></td>';
	print '<td style="padding: 0px 20px"><a href="forum_messages.pl?action=edit&id='.$tid.'&page='.$page.'">Редактировать</a></td>';
	print '</tr></table></td></tr>';
} elsif (!$allow_post) {
	print '<tr class="footertr"><td colspan=3></td></tr>';
}
print '</table>';
print '<div align="center" style="padding-top:5px;">'.$nav_pages.'</div>';
print '<div align="center" class="newt"><a href="forum_thread.pl?id='.$forum->{fid}.'">К списку тем</a></div>';
if (@bans) {
	print '<b>';
	print join '<br>', map {
		"Вы забанены смотрителем ".link_to_pers($_->[1])." до ".$_->[2]." (".$_->[0].")"
	} @bans;
	print '</b>';
}
if ($allow_post) {
	print '<div align="center"><a name="edit"></a><form method="post" action="forum_messages.pl" id="postform">';
	print '<table class="newmsg">';
	print '<input type="hidden" name="id" value="'.$tid.'"/>';
	if ($isedit) {
		print '<input type="hidden" name="editmsg" value="'.int(param('editmsg')).'"/>';
		print '<input type="hidden" name="page" value="'.$page.'"/>';
	}
	print '<input type="hidden" name="chk" value="'.$token.'"/>';
	if ($postfailreason) {
		print '<tr><td colspan=2 class="failreason">Ошибка: '.$postfailreason.'</td></tr>';
	}
	print '<tr><td>Автор:</td><td><div style="width:100%"><div id="edit_author"><b>'.link_to_pers($login{nick}).'</b></div><div id="edit_panel"></div></div></td></tr>';
	print '<tr><td></td><td>(редактирование сообщения)</td></tr>' if ($isedit);
	print '<tr><td>Сообщение:</td><td><textarea name="msg" id="msg" cols=70 rows=12>'.encode_entities($editmsg).'</textarea></td></tr>';
	if ($forum->{poll} && allowed_to('poll', $forum->{fid}, $login{acl}) && %choices) {
		my $vars = $dbh->selectcol_arrayref('SELECT choice FROM poll_votes WHERE tid=? AND uid=?', undef, $tid, $login{id});
		if (ref $vars && @$vars) {
			my $text = '';
			if (@$vars == 1) {
				$text = 'Вы уже проголосовали за вариант '.$vars->[0].' - '.$choices{$vars->[0]}->{desc};
			} else {
				$text = 'Вы уже проголосовали за варианты '.join(', ', sort {$a<=>$b} @$vars);
			}
			print '<tr><td>Опрос:</td><td>'.$text.'</td></tr>';
		} else {
			my $num = 0;
			print map {
				my $res = '';
				if ($num++ == 0) {
					$res = '<tr><td rowspan="'.scalar(keys %choices).'">Опрос:</td>';
				} else {
					$res = '<tr>';
				}
				if ($forum->{poll} == 2) {
					$res .= '<td class="pollvar"><input type="checkbox" name="choice'.$choices{$_}->{id}.'" '.(param('choice'.$choices{$_}->{id})?'checked':'').'>'.encode_entities($choices{$_}->{desc}).'</input></td></tr>';
				} else {
					$res .= '<td class="pollvar"><input type="radio" name="choice" value="'.$choices{$_}->{id}.'" '.(param('choice')==$choices{$_}->{id}?'checked':'').'>'.encode_entities($choices{$_}->{desc}).'</input></td></tr>';
				}
				$res;
			} sort {$a<=>$b} keys %choices;
		}
	}
	print '</table>';
	print '<br><input id="btn" type="submit" value="'.($isedit?'Редактировать':'Отправить').' (Ctrl+Enter)"/></form></div>';
}

$dbh->disconnect();

print end_html();

}

1;
