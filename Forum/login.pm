package Forum::login;
use strict;
use utf8;
use DBI;
use CGI qw/-utf8 :standard/;
use CGI::Cookie;
use Forum::Func;
use base 'Exporter';

our @EXPORT_OK = qw(main);

sub try_auth
{
	my $success = 0;
	my $remote = get_remote_hash();
	my $dbh = connect_db();
	return 'Слишком много попыток авторизации, подождите немного.' if (!check_limits($dbh, $remote, 'auth', [5, 40, 100]));
	my $nick = param('nick');
	$nick =~ s/^\s*|\s+$//g;
	my $pass = param('pass');
	my @res = @{$dbh->selectall_arrayref('SELECT id,password FROM users WHERE nick=?', undef, $nick)};
	foreach (@res) {
		if (crypt_password($pass, $_->[1]) eq $_->[1]) {
			$success = 1;
			make_login($dbh, $_->[0]);
			last;
		}
	}
	$dbh->disconnect();
	if ($success) {
		return '';
	}
	return 'Пароль неверен. Если вы забыли пароль, можете зарегистрироваться заново.';
}
	
sub main
{
	my $failreason = '';
	if (param('nick') && param('pass')) {
		$failreason = try_auth();
		if ($failreason eq '') {
			exit;
		}
	}

	print header(
		-type => 'text/html',
		-charset => 'UTF-8',
	);
	print_start_html('Вход');

	print '<table align="center">
	<form action="login.pl" method="POST">';
	if ($failreason) {
		print '<tr><td colspan=2 class="failreason">Ошибка: '.$failreason.'</td></tr>';
	}
print <<EOF
	<tr>
		<td>Ваш ник:</td>
		<td><input name="nick" type="text"/></td>
	</tr>
	<tr>
		<td>Пароль:</td>
		<td><input name="pass" type="password"/></td>
	</tr>
	<tr>
		<td align="center" colspan=2><input class="button" type="submit" name="login" value="Войти"/></td>
	</tr>
</form>
<form action="register.pl" method="POST">
	<tr>
		<td align="center" colspan=2><input class="button" type="submit" name="reg" value="Регистрация"/></td>
	</tr>
</form>
</table>
EOF
;

	print end_html();
}

1;
