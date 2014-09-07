package Forum::group_adm;
use strict;
use utf8;
use DBI;
use POSIX;
use CGI qw/-utf8 :standard/;
use URI::Escape;
use Forum::Func;
use base 'Exporter';

our @EXPORT_OK = qw(main);

sub main
{
my $gid = int(param('id'));
if ($gid == 0) {
	print redirect('settings.pl');
	exit;
}

our $dbh = connect_db();
my %login = get_login($dbh);
if (!$login{id}) {
	return_smth('forum.pl');
	$dbh->disconnect();
	exit;
}

my $token = gen_crc($login{sid}, 'groupmod'.$gid);

my $my_group = $dbh->selectcol_arrayref('SELECT groups.role FROM groups WHERE gid=? AND uid=?', undef, $gid, $login{id});
if (!(ref($my_group) && ($my_group->[0] =~ 'adm' || $my_group->[0] =~ 'verb'))) {
	print redirect('settings.pl');
	$dbh->disconnect();
	exit;
}

if (param('chk') == $token) {
	my $failreason = '';
	my $uid = $login{id};
	my $remove = int param('remove');
	my $change = int param('change');
	my $add = param('add');
	if (param('action') eq 'selfrevoke' && $my_group->[0] =~ 'adm') {
		$dbh->do('UPDATE groups SET role=REPLACE(role, "adm", "") WHERE gid=? AND uid=?', undef, $gid, $login{id});
		$failreason = 'Права убраны';
	} elsif ($remove && $my_group->[0] =~ 'adm') {
		if ($remove == $login{id}) {
			$failreason = 'Вы пытаетесь удалить самого себя. Если вы действительно хотите выйти, сначала снимите с себя права админа.';
		} elsif ($dbh->do('DELETE FROM groups WHERE gid=? AND uid=?', undef, $gid, $remove) eq '0E0') {
			$failreason = 'Ошибка при удалении записи';
		} else {
			$failreason = 'Запись успешно удалена';
		}
	}
	if ($change && $my_group->[0] =~ 'adm') {
		my $attr = param('attr');
		if ($change == $login{id} && $attr eq 'adm') {
			if ((${$dbh->selectcol_arrayref('SELECT count(*) FROM groups WHERE gid=? AND FIND_IN_SET("adm",role)>0;', undef, $gid)}[0] > 1) || (${$dbh->selectcol_arrayref('SELECT count(*) FROM groups WHERE gid=?', undef, $gid)}[0] <= 1)) {
				print redirect('group_adm.pl?id='.$gid.'&selfrevoke=1');
				$dbh->disconnect();
				exit;
			} else {
				$failreason = 'Прежде, чем убрать себе права админа форума, назначьте их кому-либо.';
			}
		} elsif ($dbh->do('UPDATE groups SET role=if(FIND_IN_SET(?,role)>0,REPLACE(role,?,""),CONCAT_WS(",",role,?)) WHERE gid=? AND uid=?', undef, $attr, $attr, $attr, $gid, $change) eq '0E0') {
			$failreason = 'Ошибка при изменении записи';
		} else {
			$failreason = 'Запись успешно изменена';
		}
	}
	if (defined $add && $my_group->[0] =~ 'verb') {
		$add =~ s/^\s+|\s+$//g;
		my $id = $dbh->selectrow_array('SELECT id FROM users WHERE nick=?', undef, $add);
#		if (not defined $id) {
#			$id = add_user_skel($dbh, $add);
#		}
		if (not defined $id) {
			$failreason = 'Ошибка';
		} else {
			if ($dbh->do('INSERT INTO groups (uid,gid,role,accepted) VALUES (?,?,"user",0) ON DUPLICATE KEY UPDATE uid=uid', undef, $id, $gid) eq '0E0') {
				$failreason = 'Ошибка при добавлении записи';
			} else {
				$failreason = 'Запись успешно добавлена';
			}
		}
	}
	print redirect('group_adm.pl?id='.$gid.'&res='.uri_escape_utf8($failreason));
	$dbh->disconnect();
	exit;
}

my $gname = $dbh->selectrow_array('SELECT `desc` FROM groupdesc WHERE gid=?', undef, $gid);
my @group = @{$dbh->selectall_arrayref('SELECT users.id,users.nick,groups.role FROM groups JOIN users ON users.id=groups.uid WHERE gid=? ORDER BY nick ASC', undef, $gid)};

print header(
	-type => 'text/html',
	-charset => 'UTF-8',
);
print_start_html('Группа');

print '<div class="path"><a href="forum.pl">Форумы</a> &rarr; <a href="settings.pl">Настройки</a> &rarr; <a href="group_adm.pl?id='.$gid.'">Управление группой "'.$gname.'"</a></div>';

if (param('selfrevoke')) {
	print '<form method="post" action="group_adm.pl">';
	print 'Действительно ли вы хотите убрать у себя права на эту группу? Действие может быть необратимо. ';
	print '<input type="hidden" name="id" value="'.$gid.'"/>';
	print '<input type="hidden" name="action" value="selfrevoke"/>';
	print '<input type="hidden" name="chk" value="'.$token.'"/>';
	print '<input type="submit" value="да"/>';
	print '</form>';
	$dbh->disconnect();
	print end_html();
	exit;
}

print '<div align="center">';
my $failreason = encode_entities(param('res'));
print "<b>".$failreason."</b><br>" if ($failreason);

if ($my_group->[0] =~ /adm/ || $my_group->[0] =~ /verb/) {
print '<table class="mt" style="width:70%">
	<tr class="toptr">
		<th width="10%"></th>
		<th width="30%" align="center">Ник</th>
		<th width="10%" align="center">Админ</th>
		<th width="10%" align="center">Модер</th>
		<th width="10%" align="center">Верб</th>
		<th width="30%" align="center"></th>
</tr>';

my $num = 0;
foreach (@group) {
	my ($id, $nick, $role) = @$_;
	my $class = $num++ % 2 ? 'm1' : 'm2';
	print '<tr class="'.$class.'">';
	print '<td class="br">'.$num.'</td>';
	print '<td class="br">'.link_to_pers($nick).'</td>';
	my $adm = $my_group->[0] =~ /adm/;
	print join('', map {
		my $res = '<td align="center" class="br">';
		if ($role =~ /$_/) {
			$res .= ($adm?'<a href="group_adm.pl?id='.$gid.'&change='.$id.'&attr='.$_.'&to=no&chk='.$token.'">':'').'<b>да</b>'.($adm?'</a>':'');
		} else {
			$res .= ($adm?'<a href="group_adm.pl?id='.$gid.'&change='.$id.'&attr='.$_.'&to=yes&chk='.$token.'">':'').'нет'.($adm?'</a>':'');;
		}
		$res .= '</td>';
		$res;
	} ('adm', 'mod', 'verb'));
	print '<td align="center">'.($adm?'<a href="group_adm.pl?id='.$gid.'&remove='.$id.'&chk='.$token.'">(выгнать)</a>':'').'</td>';
	print '</tr>';
}
print '<tr class="toptr">
		<th colspan=6></th>
</tr></table>';

print '<br>';
}

if ($my_group->[0] =~ /verb/) {
print '<form action="group_adm.pl?id='.$gid.'&chk='.$token.'" method="POST">';
print '<table class="mt" style="width:70%">
	<tr class="toptr">
		<th colspan=2>Приглашение игрока</th>
</tr>';
print '<tr class="m2">';
print '<td class="br"><input name="add" type="text" style="width:100%"/></td>';
print '<td><input type="submit" value="добавить"/><input type="hidden" name="id" value="'.$gid.'"/><input type="hidden" name="chk" value="'.$token.'"/></td>';
print '</tr>';
print '<tr class="m1"><td colspan=2><small>(*) игрок увидит форум только после принятия приглашения в настройках</small></td></tr>';
print '<tr class="toptr">
		<th colspan=2></th>
</tr>';
print '</table></form></div>';
}

$dbh->disconnect();

print end_html();
}
