package Forum::SubDBI;
use strict;
use DBI;
use vars qw(@ISA);
@ISA = qw(DBI);

package Forum::SubDBI::db;
use strict;
use vars qw(@ISA);
use Forum::Adds qw(cSPACE);
@ISA = qw(DBI::db);

sub prepare {
	my ($dbh, @args) = @_;
	if (cSPACE()) {
		$args[0] =~ s/::([a-z_]+)/"$1"eq'users'||"$1"eq'logins'?"s_$1":"f_$1"/ieg;
	} else {
		$args[0] =~ s/:://g;
	}
	$dbh->SUPER::prepare(@args);
}

sub do {
	my ($dbh, @args) = @_;
	if (cSPACE()) {
		$args[0] =~ s/::([a-z_]+)/"$1"eq'users'||"$1"eq'logins'?"s_$1":"f_$1"/ieg;
	} else {
		$args[0] =~ s/:://g;
	}
	$dbh->SUPER::do(@args);
}

package Forum::SubDBI::st;
use vars qw(@ISA);
@ISA = qw(DBI::st);

1;
